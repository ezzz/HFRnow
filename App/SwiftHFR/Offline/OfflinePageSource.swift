import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
import HFRStorage

// Port of Classes/OfflineStorage.m (getDataFromTopicOffline, `:430`, no caller) @ 2440d79. Differences: the saved HTML goes through the same parsers as a live page, so a parser fix
// also applies to pages saved earlier; a page never saved is an error, not a blank page (GAP-180, LOT-139).
/// The reader's page source over the saved pages: no network, no session, nothing recorded.
struct OfflinePageSource: TopicPageSource {
    let store: any OfflineStoring
    let normalizer: any MessageContentNormalizing

    func page(for target: ReaderTarget) async throws(ListLoadError) -> ReaderPage {
        // A `numreponse` link lets HFR pick the page (R25): offline there is nobody to ask.
        guard case .topic(let topic) = target.source, target.numreponse == nil else { throw .notSaved }
        let saved: OfflinePage?
        do throws(OfflineStoreError) {
            saved = try await store.page(target.page, of: topic)
        } catch {
            switch error {
            case .invalidTopic: throw .notSaved
            case .unsupportedVersion, .unreadable: throw .savedPageUnreadable
            default: throw .unreadable
            }
        }
        guard let saved else { throw .notSaved }
        if Task.isCancelled { throw .cancelled }
        guard let request = try? HFREndpoint.topicPage(topic: topic, page: saved.page) else { throw .unreadable }
        // The page number comes from the URL, as for a page served by HFR (`TopicPageMetadataParser`).
        return try LiveTopicPageSource.parse(saved.html, pageURL: request.url, normalizer: normalizer)
    }
}
