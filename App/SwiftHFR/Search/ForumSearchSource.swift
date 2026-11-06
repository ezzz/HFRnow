import HFRClient
import HFRModels
import HFRNetwork

/// What the search screen needs from the forum: the first results page of a query, and the pages after it.
protocol ForumSearchSource: Sendable {
    /// The first results page of `query` (LOT-046: POST, waiting page, GET).
    func search(_ query: GlobalSearchQuery) async throws(ListLoadError) -> TopicListPage
    /// Another results page, from a pager path of a previous page.
    func page(atPath path: String) async throws(ListLoadError) -> TopicListPage
}

/// The live source: `GlobalSearchFlow` (LOT-046, cookie-less transport) with the account's token when one is logged in.
///
/// The network path is the engine's, unchanged. A banned word never reaches it: the model refuses first.
struct LiveForumSearchSource: ForumSearchSource {
    let session: HFRSession
    let flow = GlobalSearchFlow()

    func search(_ query: GlobalSearchQuery) async throws(ListLoadError) -> TopicListPage {
        // Legacy sent its app-wide token (`ObjCForumSearchWorker.m:159`); the account's, or empty, is what the engine takes.
        let token = await session.hashCheck ?? ""
        do throws(GlobalSearchError) {
            return try await flow.search(query, hashCheck: token).page
        } catch {
            throw Self.loadError(error)
        }
    }

    func page(atPath path: String) async throws(ListLoadError) -> TopicListPage {
        do throws(GlobalSearchError) {
            return try await flow.page(atPath: path).page
        } catch {
            throw Self.loadError(error)
        }
    }

    /// Maps the engine's failure to what the list screens show.
    static func loadError(_ error: GlobalSearchError) -> ListLoadError {
        switch error {
        case .network(let failure): ListLoadError(failure)
        case .page(let failure): ListLoadError(failure)
        case .noResultsPage: .unreadable
        case .bannedWord, .invalidPage: .other
        }
    }
}

/// A source with no forum behind it (previews and tests that never search).
struct UnavailableForumSearch: ForumSearchSource {
    func search(_ query: GlobalSearchQuery) async throws(ListLoadError) -> TopicListPage { throw .other }
    func page(atPath path: String) async throws(ListLoadError) -> TopicListPage { throw .other }
}
