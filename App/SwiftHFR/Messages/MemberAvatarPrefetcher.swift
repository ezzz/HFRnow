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
    /// Profiles are refused to this session: no login, or HFR's 401/403 (#1363). Asking again cannot help until a login is
    /// installed in the session (a re-login keeps the same session object, #1195) or the account changes.
    case refused
}

/// Finds a member's avatar from the pseudo alone (#714).
protocol MemberAvatarLookup: Sendable {
    /// The avatar on `pseudo`'s public profile, `.none` when HFR says there is none, `.failed` when the exchange failed.
    func avatar(forPseudo pseudo: String) async -> MemberAvatarLookupResult
    /// The login the lookups depend on; a new `generation` lifts a refusal.
    func loginState() async -> ProfileLoginState
}

/// The live lookup, two GETs: `profilebdd.php`'s `301`, cookie-less, gives the member id without being followed (`R716a`, the
/// same without cookies `R716c`; an unknown pseudo names an empty id and stops there, `R716d`), then the public profile through
/// `profiles` (`LiveUserProfileSource`, which sends the account's session since HFR refuses it without, `R1363a`, #1363, reads
/// only `/hfr/profil-<id>.htm` and parses it with `UserProfileParser`). Without a login nothing is sent, not even the id lookup.
struct LiveMemberAvatarLookup: MemberAvatarLookup {
    let fetcher: PageFetcher
    let profiles: LiveUserProfileSource

    func loginState() async -> ProfileLoginState { await profiles.loginState() }

    func avatar(forPseudo pseudo: String) async -> MemberAvatarLookupResult {
        // The profile would be refused: the id lookup would leave for nothing.
        guard await profiles.isLoggedIn() else { return .refused }
        let memberID: Int?
        do throws(NetworkError) {
            memberID = try await fetcher.memberID(pseudo: pseudo, as: .anonymous)
        } catch {
            return .failed
        }
        // An empty id (`R716d`) or another answer: HFR names no member.
        guard let memberID else { return .none }
        do throws(ListLoadError) {
            let profile = try await profiles.profile(memberID: memberID)
            return profile.avatarURL.map(MemberAvatarLookupResult.avatar) ?? .none
        } catch {
            return error == .profileAccessDenied || error == .profileLoginRequired ? .refused : .failed
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
/// leaves the screen before its turn gives the turn away untried, so only rows still shown are fetched. A refusal (no login, HFR's
/// 401/403, #1363) stops every lookup, each would be refused the same way, until the session's login changes (a re-login keeps
/// the same session and environment, #1195).
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
    /// Set by a refused lookup to the login generation it ran under: no lookup runs until the generation moves.
    private var suspendedGeneration: Int?

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

    /// The app's prefetcher: cookie-less id lookups through `fetcher`, profiles with `session`, the standard avatar cache,
    /// `store` for the download.
    static func live(
        fetcher: PageFetcher, session: HFRSession, store: AvatarStore, cache: AvatarCache = AvatarCache(cache: .standard)
    ) -> MemberAvatarPrefetcher {
        let lookup = LiveMemberAvatarLookup(fetcher: fetcher, profiles: LiveUserProfileSource(session: session))
        return MemberAvatarPrefetcher(
            lookup: lookup, spacing: liveSpacing, retryDelay: liveRetryDelay,
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
        if let suspended = suspendedGeneration, await lookup.loginState().generation != suspended { suspendedGeneration = nil }
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
        // Read before the lookup: a login installed while it runs must not be the one a refusal suspends.
        let generation = await lookup.loginState().generation
        // Detached: once started, the lookup ends even if the row scrolls away, since the pseudo is not asked again at once.
        let outcome = await Task.detached(priority: .utility) { () -> LookupOutcome in
            await Self.outcome(of: lookup.avatar(forPseudo: name), for: name, offer: offer, hasAvatar: hasAvatar)
        }.value
        switch outcome {
        case .answered:
            retryAt[key] = nil
        case .failed:
            tried.remove(key)
            retryAt[key] = ContinuousClock.now.advanced(by: retryDelay)
        case .refused:
            tried.remove(key)
            suspendedGeneration = generation
        }
    }

    private enum LookupOutcome {
        case answered, failed, refused
    }

    /// What a lookup's result means for the pseudo; an avatar is offered first.
    private static func outcome(
        of result: MemberAvatarLookupResult, for name: String, offer: @Sendable (String, URL) async -> Void,
        hasAvatar: @Sendable (String) -> Bool
    ) async -> LookupOutcome {
        switch result {
        case .none:
            return .answered
        case .failed:
            return .failed
        case .refused:
            return .refused
        case .avatar(let url):
            await offer(name, url)
            // The store keeps only a downloaded image: a failed download is a failure too.
            return hasAvatar(name) ? .answered : .failed
        }
    }

    /// The lookup's login now (tests check the app wires the environment's session).
    func currentLoginState() async -> ProfileLoginState { await lookup.loginState() }

    /// Whether `key` may be looked up now: not suspended, never answered for, and past its retry time after a failure.
    private func isDue(_ key: String) -> Bool {
        guard suspendedGeneration == nil, !tried.contains(key) else { return false }
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
