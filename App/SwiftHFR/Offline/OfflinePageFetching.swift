import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// A topic page fetched for saving: the HTML and the page number HFR served (it may differ from the one asked, R24).
struct FetchedOfflinePage: Sendable, Equatable {
    let html: String
    let page: Int
}

/// Fetches the pages to save. The implementation must not use the account session (see `LiveOfflinePageFetcher`).
protocol OfflinePageFetching: Sendable {
    func fetch(topic: TopicID, page: Int) async throws(ListLoadError) -> FetchedOfflinePage
}

/// Fetches without cookies, whatever the page: a logged-in read would mark the topic's flags read (HFR-PROTOCOL §7 E25, LOT-045)
/// and put the account's `hash_check` in the page, which the store refuses. A page that is not a topic page (maintenance, a
/// refusal notice) is never handed on: the store would keep it as the topic's page.
struct LiveOfflinePageFetcher: OfflinePageFetching {
    let fetcher: PageFetcher
    let normalizer: any MessageContentNormalizing

    func fetch(topic: TopicID, page: Int) async throws(ListLoadError) -> FetchedOfflinePage {
        let fetched: FetchedTopicPage
        do throws(NetworkError) {
            fetched = try await fetcher.topicPage(topic: topic, page: page, as: .anonymous)
        } catch {
            throw ListLoadError(error)
        }
        // Only the canonical URL says which page HFR served; without it nothing can be filed under a page number.
        guard let location = fetched.location, location.topic == topic.topic else { throw .unreadable }
        let parsed = try LiveTopicPageSource.parse(fetched.page.text, pageURL: fetched.page.finalURL, normalizer: normalizer)
        guard !parsed.messages.isEmpty else { throw .unreadable }
        return FetchedOfflinePage(html: fetched.page.text, page: location.page)
    }
}
