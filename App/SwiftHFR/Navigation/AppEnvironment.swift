import HFRNetwork

/// Composition of the engine objects the screens share. The account and login lot replaces the anonymous session here.
struct AppEnvironment {
    let session: HFRSession
    let dataSource: any ForumDataSource

    /// The app's environment: a session with no cookie yet and the live data source.
    @MainActor
    static func live() -> AppEnvironment {
        let session = HFRSession()
        return AppEnvironment(session: session, dataSource: LiveForumDataSource(fetcher: PageFetcher(session: session)))
    }

    /// Pseudo of the signed-in account, nil when logged out.
    var accountName: @Sendable () async -> String? {
        { [session] in await session.userKey() }
    }
}
