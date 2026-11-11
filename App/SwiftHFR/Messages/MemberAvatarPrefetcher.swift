import Foundation
import HFRNetwork
import HFRStorage

/// Finds a member's avatar from the pseudo alone (#714).
protocol MemberAvatarLookup: Sendable {
    /// The avatar on `pseudo`'s public profile; nil when the member is unknown, has none, or a fetch fails.
    func avatarURL(forPseudo pseudo: String) async -> URL?
}

/// The live lookup, two cookie-less GETs: `profilebdd.php`'s `301` gives the member id without being followed (`R716a`, the
/// same without cookies `R716c`; an unknown pseudo names an empty id and stops there, `R716d`), then the public profile
/// (`R56a`, `R56b`) through `LiveUserProfileSource`, which reads only `/hfr/profil-<id>.htm` and parses it with `UserProfileParser`.
struct LiveMemberAvatarLookup: MemberAvatarLookup {
    let fetcher: PageFetcher

    func avatarURL(forPseudo pseudo: String) async -> URL? {
        guard let memberID = try? await fetcher.memberID(pseudo: pseudo, as: .anonymous) else { return nil }
        return try? await LiveUserProfileSource(fetcher: fetcher).profile(memberID: memberID).avatarURL
    }
}

// No legacy counterpart: legacy's MP rows only read the avatars cached while reading pages (`MPListView.swift:893-930` @ 87fe0d1c,
// GAP-230); this fetch is the #714 change to it.
/// Fills the avatar cache for the one-to-one MP rows on screen whose correspondent has no cached avatar (#714): looks the member
/// up (`MemberAvatarLookup`) and hands the avatar to `AvatarStore`, which keeps its own rules (forum image host, no cookie,
/// 256 KiB, 24 h).
///
/// Lookups run one at a time, at least `spacing` apart. Each pseudo is looked up at most once per prefetcher (one per session,
/// `AppEnvironment`), whatever the outcome: a member without avatar or a failed fetch is not asked again until the next
/// session. A row that leaves the screen before its turn gives the turn away untried, so only rows still shown are fetched.
actor MemberAvatarPrefetcher {
    /// The time between two lookups of the live prefetcher: each lookup is two page requests.
    static let liveSpacing = Duration.seconds(1)

    private let lookup: any MemberAvatarLookup
    private let offer: @Sendable (_ pseudo: String, _ url: URL) async -> Void
    private let hasAvatar: @Sendable (_ pseudo: String) -> Bool
    private let spacing: Duration
    private var tried: Set<String> = []
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var lastStart: ContinuousClock.Instant?

    /// A prefetcher that offers what `lookup` finds to `offer`, skipping pseudos for which `hasAvatar` is true.
    init(
        lookup: any MemberAvatarLookup, spacing: Duration = .zero, hasAvatar: @escaping @Sendable (_ pseudo: String) -> Bool,
        offer: @escaping @Sendable (_ pseudo: String, _ url: URL) async -> Void
    ) {
        self.lookup = lookup
        self.spacing = spacing
        self.hasAvatar = hasAvatar
        self.offer = offer
    }

    /// The app's prefetcher: cookie-less lookups through `fetcher`, the standard avatar cache, `store` for the download.
    static func live(
        fetcher: PageFetcher, store: AvatarStore, cache: AvatarCache = AvatarCache(cache: .standard)
    ) -> MemberAvatarPrefetcher {
        MemberAvatarPrefetcher(
            lookup: LiveMemberAvatarLookup(fetcher: fetcher), spacing: liveSpacing,
            // Any entry, even a stale one: the rows show it, and the pages read refresh it (`AvatarFillingTopicPageSource`).
            hasAvatar: { pseudo in (try? cache.entry(forPseudo: pseudo)) != nil },
            offer: { pseudo, url in await store.offer(pseudo: pseudo, url: url) }
        )
    }

    /// Looks `pseudo` up and offers its avatar, unless it was tried before, the cache has one, or the caller is cancelled
    /// before its turn. Returns once the avatar is stored or the lookup gave nothing.
    func prefetch(pseudo: String) async {
        let name = pseudo.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = name.lowercased()
        guard !name.isEmpty, !tried.contains(key) else { return }
        await acquireTurn()
        defer { releaseTurn() }
        if let lastStart, spacing > .zero {
            // Cancellable: a row that leaves the screen while waiting stops here and is checked below.
            try? await Task.sleep(until: lastStart.advanced(by: spacing), clock: .continuous)
        }
        guard !Task.isCancelled, !tried.contains(key), !hasAvatar(name) else { return }
        tried.insert(key)
        lastStart = .now
        let lookup = lookup
        let offer = offer
        // Detached: once started, the lookup ends even if the row scrolls away, since the pseudo is not tried again.
        await Task.detached(priority: .utility) {
            guard let url = await lookup.avatarURL(forPseudo: name) else { return }
            await offer(name, url)
        }.value
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
