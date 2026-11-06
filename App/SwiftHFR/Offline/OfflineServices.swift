import HFRNetwork
import HFRStorage

/// What the reader and the settings need for offline reading (LOT-139): the saved pages, how to fetch pages to save, and the
/// reader source over the saved pages.
struct OfflineServices: Sendable {
    let store: any OfflineStoring
    let fetcher: any OfflinePageFetching
    let normalizer: any MessageContentNormalizing

    /// The reader's source over the saved pages.
    var pageSource: OfflinePageSource { OfflinePageSource(store: store, normalizer: normalizer) }

    /// The device's store and cookie-less fetches.
    static func live(fetcher: PageFetcher) -> OfflineServices {
        let normalizer = LiveContentNormalizer()
        return OfflineServices(
            store: LiveOfflineStore(), fetcher: LiveOfflinePageFetcher(fetcher: fetcher, normalizer: normalizer), normalizer: normalizer
        )
    }
}
