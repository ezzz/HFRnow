import HFRNetwork
import HFRStorage

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
    /// Topic pages for the reader (LOT-083), fetched with this session.
    let topicPages: any TopicPageSource
    /// Image client and settings of the reader.
    let reader: ReaderServices
    /// The private message list (LOT-126), fetched with this session.
    let privateMessages: any PrivateMessageSource
    /// Reply composer of the current account (LOT-084); nil when logged out.
    let composer: ComposerServices?

    /// The environment for `session`.
    static func make(session: HFRSession, accountName: String?) -> AppEnvironment {
        let fetcher = PageFetcher(session: session)
        let source = LiveForumDataSource(fetcher: fetcher, transport: session)
        NetworkMonitor.start()
        let pages = LiveTopicPageSource(fetcher: fetcher, session: session, normalizer: LiveContentNormalizer())
        let reader = ReaderServices(
            imageFetcher: ReaderImageFetcher(),
            settings: .live(store: UserDefaultsSettingsStore(), isOnWiFi: { NetworkMonitor.shared.isOnWiFi })
        )
        return AppEnvironment(
            session: session, dataSource: source, visibility: ForumVisibility(), currentAccountName: accountName,
            topicPages: pages, reader: reader, composer: .live(session: session, account: accountName),
            privateMessages: LivePrivateMessageSource(fetcher: fetcher)
        )
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

extension AppEnvironment {
    /// The model of the Messages screen over this session; the reader opens a conversation with the same page source.
    @MainActor
    func makeMessageList() -> MessageListModel {
        MessageListModel(
            source: privateMessages, isLoggedIn: isLoggedIn, topicPages: topicPages, renderOptions: reader.settings.renderOptions
        )
    }
}
