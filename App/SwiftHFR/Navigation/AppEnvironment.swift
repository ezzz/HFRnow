import HFRNetwork

/// Composition of the engine objects the screens share. The account and login lot replaces the anonymous session here.
struct AppEnvironment {
    let session: HFRSession
    let dataSource: any ForumDataSource
    /// The one place the Apple category rule and the review account name live (Q-7); the AQ feed reuses it.
    let visibility: ForumVisibility

    /// The app's environment: a session with no cookie yet and the live data source.
    @MainActor
    static func live() -> AppEnvironment {
        let session = HFRSession()
        let source = LiveForumDataSource(fetcher: PageFetcher(session: session), transport: session)
        return AppEnvironment(session: session, dataSource: source, visibility: ForumVisibility())
    }

    /// Pseudo of the signed-in account, nil when logged out.
    var accountName: @Sendable () async -> String? {
        { [session] in await session.userKey() }
    }

    /// Whether the session holds a usable login cookie.
    var isLoggedIn: @Sendable () async -> Bool {
        { [session] in await session.isLoggedIn() }
    }
}
