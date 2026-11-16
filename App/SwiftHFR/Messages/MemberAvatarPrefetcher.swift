import Foundation
import HFRNetwork
import HFRStorage

/// What a member lookup found.
enum MemberAvatarLookupResult: Sendable, Equatable {
    /// The avatar on the member's profile.
    case avatar(URL)
    /// HFR answered: no such member, or a profile without avatar. Not asked again in the session.
    case none
    /// The exchange failed (offline, timeout, a server error, an unreadable page): worth asking again later.
    case failed
}

/// Finds a member's avatar from the pseudo alone (#714).
protocol MemberAvatarLookup: Sendable {
    /// The avatar on `pseudo`'s public profile, `.none` when HFR says there is none, `.failed` when the exchange failed.
    func avatar(forPseudo pseudo: String) async -> MemberAvatarLookupResult
}

/// The live lookup, two cookie-less GETs: `profilebdd.php`'s `301` gives the member id without being followed (`R716a`, the
/// same without cookies `R716c`; an unknown pseudo names an empty id and stops there, `R716d`), then the public profile
/// (`R56a`, `R56b`) through `LiveUserProfileSource`, which reads only `/hfr/profil-<id>.htm` and parses it with `UserProfileParser`.
struct LiveMemberAvatarLookup: MemberAvatarLookup {
    let fetcher: PageFetcher

    func avatar(forPseudo pseudo: String) async -> MemberAvatarLookupResult {
        let memberID: Int?
        do throws(NetworkError) {
            memberID = try await fetcher.memberID(pseudo: pseudo, as: .anonymous)
        } catch {
            return .failed
        }
        // An empty id (`R716d`) or another answer: HFR names no member.
        guard let memberID else { return .none }
        do throws(ListLoadError) {
            let profile = try await LiveUserProfileSource(fetcher: fetcher).profile(memberID: memberID)
            return profile.avatarURL.map(MemberAvatarLookupResult.avatar) ?? .none
        } catch {
            return .failed
        }
    }
}

// No legacy counterpart: legacy's MP rows only read the avatars cached while reading pages (`MPListView.swift:893-930` @ 87fe0d1c,
// GAP-230); this fetch is the #714 change to it.
/// Fills the avatar cache for the one-to-one MP rows on screen whose correspondent has no cached avatar (#714): looks the member
/// up (`MemberAvatarLookup`) and hands the avatar to `AvatarStore`, which keeps its own rules (forum image host, no cookie,
/// 256 KiB, 24 h).
///
/// Lookups run one at a time, at least `spacing` apart. A pseudo HFR answered for (avatar stored, unknown member, no avatar) is
/// not looked up again in the prefetcher's life (one per session, `AppEnvironment`); a failed exchange, or an avatar the store
/// did not keep, is retried only after `retryDelay`, so a list opened offline recovers without asking twice in a row. A row that
/// leaves the screen before its turn gives the turn away untried, so only rows still shown are fetched.
actor MemberAvatarPrefetcher {
    /// The time between two lookups of the live prefetcher: each lookup is two page requests.
    static let liveSpacing = Duration.seconds(1)
    /// The time before a failed lookup of the live prefetcher may run again.
    static let liveRetryDelay = Duration.seconds(60)

    private let lookup: any MemberAvatarLookup
    private let offer: @Sendable (_ pseudo: String, _ url: URL) async -> Void
    private let hasAvatar: @Sendable (_ pseudo: String) -> Bool
    private let spacing: Duration
    private let retryDelay: Duration
    private var tried: Set<String> = []
    /// Pseudos whose last lookup failed, with the time it may run again.
    private var retryAt: [String: ContinuousClock.Instant] = [:]
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var lastStart: ContinuousClock.Instant?

    /// A prefetcher that offers what `lookup` finds to `offer`, skipping pseudos for which `hasAvatar` is true.
    init(
        lookup: any MemberAvatarLookup, spacing: Duration = .zero, retryDelay: Duration = .seconds(60),
        hasAvatar: @escaping @Sendable (_ pseudo: String) -> Bool,
        offer: @escaping @Sendable (_ pseudo: String, _ url: URL) async -> Void
    ) {
        self.lookup = lookup
        self.spacing = spacing
        self.retryDelay = retryDelay
        self.hasAvatar = hasAvatar
        self.offer = offer
    }

    /// The app's prefetcher: cookie-less lookups through `fetcher`, the standard avatar cache, `store` for the download.
    static func live(
        fetcher: PageFetcher, store: AvatarStore, cache: AvatarCache = AvatarCache(cache: .standard)
    ) -> MemberAvatarPrefetcher {
        MemberAvatarPrefetcher(
            lookup: LiveMemberAvatarLookup(fetcher: fetcher), spacing: liveSpacing, retryDelay: liveRetryDelay,
            // Any entry, even a stale one: the rows show it, and the pages read refresh it (`AvatarFillingTopicPageSource`).
            hasAvatar: { pseudo in (try? cache.entry(forPseudo: pseudo)) != nil },
            offer: { pseudo, url in await store.offer(pseudo: pseudo, url: url) }
        )
    }

    /// Looks `pseudo` up and offers its avatar, unless HFR already answered for it, its last failure is too recent, the cache
    /// has one, or the caller is cancelled before its turn. Returns once the avatar is stored or the lookup gave nothing.
    func prefetch(pseudo: String) async {
        let name = pseudo.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = name.lowercased()
        guard !name.isEmpty, isDue(key) else { return }
        await acquireTurn()
        defer { releaseTurn() }
        if let lastStart, spacing > .zero {
            // Cancellable: a row that leaves the screen while waiting stops here and is checked below.
            try? await Task.sleep(until: lastStart.advanced(by: spacing), clock: .continuous)
        }
        guard !Task.isCancelled, isDue(key), !hasAvatar(name) else { return }
        // Marked before the lookup: a row asking again while it runs waits for the turn and then finds it tried.
        tried.insert(key)
        lastStart = .now
        let lookup = lookup
        let offer = offer
        let hasAvatar = hasAvatar
        // Detached: once started, the lookup ends even if the row scrolls away, since the pseudo is not asked again at once.
        let failed = await Task.detached(priority: .utility) { () -> Bool in
            switch await lookup.avatar(forPseudo: name) {
            case .none:
                return false
            case .failed:
                return true
            case .avatar(let url):
                await offer(name, url)
                // The store keeps only a downloaded image: a failed download is a failure too.
                return !hasAvatar(name)
            }
        }.value
        if failed {
            tried.remove(key)
            retryAt[key] = ContinuousClock.now.advanced(by: retryDelay)
        } else {
            retryAt[key] = nil
        }
    }

    /// Whether `key` may be looked up now: never answered for, and past its retry time after a failure.
    private func isDue(_ key: String) -> Bool {
        guard !tried.contains(key) else { return false }
        guard let retry = retryAt[key] else { return true }
        return ContinuousClock.now >= retry
    }

    private func acquireTurn() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Hands the turn to the next waiter (still busy), or frees it.
    private func releaseTurn() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
