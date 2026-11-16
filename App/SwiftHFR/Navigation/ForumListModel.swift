import HFRModels
import Observation

// Port of HFRswift/Swift/MainWindow.swift (CategoriesListViewModel) @ 87fe0d1c. Differences: forums from LOT-021; the sub-forums
// stay known here (the topic list's picker and the "N sous-forums" count read them, GAP-020, 022).
/// One forum entry of the sidebar.
struct ForumRow: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let source: TopicSource
}

/// A category of the sidebar with its own list and its sub-forums.
struct ForumSection: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// The category's own list first ("Tous les sujets"), then its sub-forums.
    let rows: [ForumRow]
    let categoryID: CategoryID?

    /// What the category row opens: the category's whole list.
    var source: TopicSource { rows[0].source }
    /// How many sub-forums the home page (and the completion table, LOT-021) gave for it.
    var subforumCount: Int { rows.count - 1 }
    /// The category's image (`ForumCategoryIcon`).
    var iconName: String { ForumCategoryIcon.assetName(for: categoryID) }
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

    /// The category `source` belongs to, whether it is the category's own list or one of its sub-forums.
    func section(containing source: TopicSource) -> ForumSection? {
        sections.first { section in section.rows.contains { $0.source == source } }
    }

    private static func section(for forum: ForumCategory) -> ForumSection {
        // The category opens by its id when known (same list as its path), every sub-forum by the link the page gave.
        let own = forum.categoryID ?? ForumCatalogue.categoryID(forPath: forum.path)
        let ownSource = own.map { TopicSource.forum($0, title: forum.title) } ?? .subforum(path: forum.path, title: forum.title)
        var rows = [ForumRow(id: forum.id, title: "Tous les sujets", source: ownSource)]
        rows += forum.subforums.map { ForumRow(id: $0.path, title: $0.title, source: .subforum(path: $0.path, title: $0.title)) }
        return ForumSection(id: forum.id, title: forum.title, rows: rows, categoryID: own)
    }
}

/// State of the forum list (sidebar). Loading, refreshing and failures go through `ContentLoader`.
@MainActor
@Observable
final class ForumListModel {
    let loader = ContentLoader<ForumListContent>()
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
}
