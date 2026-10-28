import Foundation
import HFRModels
@testable import SwiftHFR

/// A scripted data source: each call is answered by a closure and recorded.
final class FakeDataSource: ForumDataSource, @unchecked Sendable {
    typealias TopicHandler = @Sendable (CategoryID, Int) async throws(ListLoadError) -> TopicListPage

    private let lock = NSLock()
    private var recorded: [String] = []
    var forumHandler: @Sendable () async throws(ListLoadError) -> ForumListPage = { ForumListPage(forums: []) }
    var topicHandler: TopicHandler = { _, page in topicPage(page: page) }
    var pathHandler: @Sendable (String, Int) async throws(ListLoadError) -> TopicListPage = { _, page in topicPage(page: page) }
    var favoritesHandler: @Sendable (TopicListFilter) async throws(ListLoadError) -> FavoritesPage = { _ in FavoritesPage() }

    /// Requests received, in order, as `forums`, `topics:<cat>:<page>` or `favorites:<filter>`.
    var requests: [String] { lock.withLock { recorded } }

    private func record(_ request: String) { lock.withLock { recorded.append(request) } }

    func forumList() async throws(ListLoadError) -> ForumListPage {
        record("forums")
        return try await forumHandler()
    }

    func topicList(category: CategoryID, page: Int) async throws(ListLoadError) -> TopicListPage {
        record("topics:\(category.queryValue):\(page)")
        return try await topicHandler(category, page)
    }

    func topicList(path: String, page: Int) async throws(ListLoadError) -> TopicListPage {
        record("path:\(path):\(page)")
        return try await pathHandler(path, page)
    }

    func favorites(filter: TopicListFilter) async throws(ListLoadError) -> FavoritesPage {
        record("favorites:\(filter.rawValue)")
        return try await favoritesHandler(filter)
    }
}

func topicSummary(_ number: Int, title: String = "Topic") -> TopicSummary {
    TopicSummary(topicID: TopicID(category: .forum(13), topic: number), title: "\(title) \(number)", path: "/t\(number)")
}

/// A forum list page `page`, with a next link unless it is page 5.
func topicPage(page: Int) -> TopicListPage {
    TopicListPage(
        topics: [topicSummary(page * 10)],
        navigation: PageNavigation(current: page, last: 5, nextPath: page < 5 ? "/next" : nil, previousPath: page > 1 ? "/prev" : nil)
    )
}
