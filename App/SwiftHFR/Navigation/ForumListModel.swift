import HFRModels
import Observation

/// One forum entry of the sidebar; `source` is nil when the forum has no known category id, so it cannot be opened.
struct ForumRow: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let source: TopicSource?
}

/// A category of the sidebar with its own list and its sub-forums.
struct ForumSection: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let rows: [ForumRow]
}

/// The forum list ready to display: Apple category already filtered (Q-7), sources resolved.
struct ForumListContent: Sendable, Equatable {
    var sections: [ForumSection]
    var isLoggedIn: Bool
    var unreadPrivateMessages: Int?

    init(page: ForumListPage, visibility: ForumVisibility, accountName: String?) {
        let forums = visibility.visible(page.forums, isLoggedIn: page.isLoggedIn, accountName: accountName)
        sections = forums.map(Self.section(for:))
        isLoggedIn = page.isLoggedIn
        unreadPrivateMessages = page.unreadPrivateMessages
    }

    private static func section(for forum: ForumCategory) -> ForumSection {
        let own = forum.categoryID ?? ForumCatalogue.categoryID(forPath: forum.path)
        var rows = [ForumRow(id: forum.id, title: "Tous les sujets", source: own.map { .forum($0, title: forum.title) })]
        rows += forum.subforums.map { link in
            let category = ForumCatalogue.categoryID(forPath: link.path)
            return ForumRow(id: link.path, title: link.title, source: category.map { .forum($0, title: link.title) })
        }
        return ForumSection(id: forum.id, title: forum.title, rows: rows)
    }
}

/// State of the forum list (sidebar). Loading, refreshing and failures go through `ContentLoader`.
@MainActor
@Observable
final class ForumListModel {
    let loader = ContentLoader<ForumListContent>()
    /// Categories the user has opened; the selected forum's category is opened by `reveal`.
    var expandedSections: Set<String> = []

    private let dataSource: any ForumDataSource
    private let visibility: ForumVisibility
    private let accountName: @Sendable () async -> String?

    /// Creates the model; `accountName` returns the pseudo of the signed-in account, nil when logged out.
    init(
        dataSource: any ForumDataSource,
        visibility: ForumVisibility = ForumVisibility(),
        accountName: @escaping @Sendable () async -> String? = { nil }
    ) {
        self.dataSource = dataSource
        self.visibility = visibility
        self.accountName = accountName
    }

    /// Loads once; later calls keep what is shown.
    func loadIfNeeded() async {
        guard loader.value == nil, !loader.isLoading else { return }
        await reload()
    }

    /// Reloads the home page, keeping the list on screen meanwhile and after a failure.
    func reload() async {
        let dataSource = dataSource
        let visibility = visibility
        let accountName = accountName
        await loader.load { () async throws(ListLoadError) -> ForumListContent in
            let page = try await dataSource.forumList()
            return ForumListContent(page: page, visibility: visibility, accountName: await accountName())
        }
    }

    /// Opens the section holding `source`, so a selection made elsewhere is visible in the sidebar.
    func reveal(_ source: TopicSource?) {
        guard let source, let sections = loader.value?.sections else { return }
        if let section = sections.first(where: { $0.rows.contains { $0.source == source } }) {
            expandedSections.insert(section.id)
        }
    }
}
