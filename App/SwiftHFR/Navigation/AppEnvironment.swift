import HFRNetwork

/// Composition of the engine objects the screens share, built for one session: the current account's, or the logged-out
/// one. Rebuilt whenever `AccountsModel.currentSessionGeneration` changes (LOT-081), so no screen keeps a previous
/// account's session or lists.
struct AppEnvironment {
    let session: HFRSession
    let dataSource: any ForumDataSource
    /// The one place the Apple category rule and the review account name live (Q-7); the AQ feed reuses it.
    let visibility: ForumVisibility
    /// The current account's key (`md_user` value, `AccountsModel.current?.id`), nil when logged out.
    let currentAccountName: String?

    /// The environment for `session`.
    static func make(session: HFRSession, accountName: String?) -> AppEnvironment {
        let source = LiveForumDataSource(fetcher: PageFetcher(session: session), transport: session)
        return AppEnvironment(session: session, dataSource: source, visibility: ForumVisibility(), currentAccountName: accountName)
    }

    /// The environment of the current account, or of the logged-out session when there is none.
    @MainActor
    static func current(of accounts: AccountsModel) -> AppEnvironment {
        make(session: accounts.forumSession, accountName: accounts.current?.id)
    }

    /// Pseudo of the current account for the Q-7 rule, nil when logged out. Read from the account list, not from the
    /// jar, so the rule and the account menu always agree.
    var accountName: @Sendable () async -> String? {
        { [currentAccountName] in currentAccountName }
    }

    /// Whether the session holds a usable login cookie (an expired current account reads as logged out).
    var isLoggedIn: @Sendable () async -> Bool {
        { [session] in await session.isLoggedIn() }
    }
}
