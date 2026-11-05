import HFRClient
import HFRModels
import HFRNetwork
import HFRParsing
import HFRStorage

/// Reads one batch of filtered messages (LOT-093). A protocol so the model is tested without the forum.
protocol FilteredPostsSource: Sendable {
    /// The messages `criteria` keeps from `page` on, until a batch is full or the topic ends; `message` skips, on the first
    /// page, the messages up to it. `progress` is called after each page.
    func batch(
        in topic: TopicID, from page: Int, after message: Int?, criteria: FilteredPostsCriteria,
        progress: @escaping @Sendable (FilteredPostsProgress) async -> Void
    ) async throws(FilteredPostsError) -> FilteredPostsBatch
}

/// The engine's flow: cookie-less page reads, so filtering never marks anything read (HFR-PROTOCOL §7 E25).
struct LiveFilteredPostsSource: FilteredPostsSource {
    func batch(
        in topic: TopicID, from page: Int, after message: Int?, criteria: FilteredPostsCriteria,
        progress: @escaping @Sendable (FilteredPostsProgress) async -> Void
    ) async throws(FilteredPostsError) -> FilteredPostsBatch {
        try await FilteredPostsFlow().posts(in: topic, from: page, after: message, criteria: criteria, progress: progress)
    }
}

/// What the post filter needs from the app: the page source, the criteria read at the start of each run and the normalizer
/// that turns a kept message into reader content.
struct FilteredPostsServices: Sendable {
    let source: any FilteredPostsSource
    /// Read at the start of every run, so a change made in Réglages applies to the next one.
    let criteria: @Sendable () -> FilteredPostsCriteria
    let normalizer: any MessageContentNormalizing

    /// Services for a build without a forum (previews, tests that never filter).
    static let unavailable = FilteredPostsServices(
        source: UnavailableFilteredPostsSource(), criteria: { FilteredPostsCriteria() }, normalizer: LiveContentNormalizer()
    )

    /// The live services. The criteria come from the settings (`filter_posts_min_quotes`, `filter_posts_quotes`), the
    /// account's pseudo and `allowlist`, the allowlist minus the blocklist (LOT-093: `FilteredPostsCriteria.allowlist`).
    static func live(
        store: any SettingsStore, pseudo: String?, allowlist: @escaping @Sendable () -> [String] = { [] }
    ) -> FilteredPostsServices {
        FilteredPostsServices(
            source: LiveFilteredPostsSource(),
            criteria: { criteria(store: store, pseudo: pseudo, allowlist: allowlist()) },
            normalizer: LiveContentNormalizer()
        )
    }

    /// The criteria the settings give: legacy's minimum (a value of 0 or less reads as 3 in the engine) and whether the
    /// allowlist counts (`filter_posts_quotes` containing `wl`).
    static func criteria(store: any SettingsStore, pseudo: String?, allowlist: [String]) -> FilteredPostsCriteria {
        FilteredPostsCriteria(
            minimumQuoteCount: store.value(for: SettingKey.quoteFilterMinimumCount), pseudo: pseudo, allowlist: allowlist,
            includesAllowlist: store.value(for: SettingKey.quoteFilterExceptions).contains(.allowlistedAuthors)
        )
    }
}

/// A source with no forum behind it.
struct UnavailableFilteredPostsSource: FilteredPostsSource {
    func batch(
        in topic: TopicID, from page: Int, after message: Int?, criteria: FilteredPostsCriteria,
        progress: @escaping @Sendable (FilteredPostsProgress) async -> Void
    ) async throws(FilteredPostsError) -> FilteredPostsBatch {
        throw .network(.invalidRequest(reason: "unavailable"))
    }
}
