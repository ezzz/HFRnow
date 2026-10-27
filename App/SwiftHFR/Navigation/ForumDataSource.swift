import HFRModels
import HFRNetwork
import HFRParsing

/// What the navigation screens need from the forum: fetch and parse, nothing else.
protocol ForumDataSource: Sendable {
    /// The home page: categories, login state, unread private messages.
    func forumList() async throws(ListLoadError) -> ForumListPage
    /// One page of a forum's topic list.
    func topicList(category: CategoryID, page: Int) async throws(ListLoadError) -> TopicListPage
    /// The favourites page for `filter` (`.favorites` or `.flagged`).
    func favorites(filter: TopicListFilter) async throws(ListLoadError) -> FavoritesPage
}

/// The live data source: `PageFetcher` (LOT-045) then the list parsers (LOT-021, 022, 024).
///
/// Lists are fetched with the account's session (flags need it); no topic page is fetched here, so nothing is marked read.
struct LiveForumDataSource: ForumDataSource {
    let fetcher: PageFetcher

    func forumList() async throws(ListLoadError) -> ForumListPage {
        let raw = try await fetch { () async throws(NetworkError) -> RawPage in try await fetcher.home() }
        do throws(ListPageFailure) {
            return try ForumListParser.parse(raw.text)
        } catch {
            throw ListLoadError(error)
        }
    }

    func topicList(category: CategoryID, page: Int) async throws(ListLoadError) -> TopicListPage {
        let raw = try await fetch { () async throws(NetworkError) -> RawPage in try await fetcher.topicList(category: category, filter: .all, page: page) }
        do throws(ListPageFailure) {
            return try TopicListParser.parse(raw.text, pageURL: raw.finalURL.absoluteString)
        } catch {
            throw ListLoadError(error)
        }
    }

    func favorites(filter: TopicListFilter) async throws(ListLoadError) -> FavoritesPage {
        let raw = try await fetch { () async throws(NetworkError) -> RawPage in try await fetcher.favorites(filter: filter) }
        do throws(ListPageFailure) {
            return try FavoritesParser.parse(raw.text)
        } catch {
            throw ListLoadError(error)
        }
    }

    private func fetch(_ request: () async throws(NetworkError) -> RawPage) async throws(ListLoadError) -> RawPage {
        do throws(NetworkError) {
            return try await request()
        } catch {
            throw ListLoadError(error)
        }
    }
}
