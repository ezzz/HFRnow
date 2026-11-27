import Foundation
import HFRModels

/// The AQ feed the app read last, kept for the life of the process (#1398): legacy reads the feed once at launch for the badge
/// (`MainWindow.swift:1609` @ 87fe0d1c), while SwiftHFR rebuilds its root on each account switch, login and logout, and builds
/// one per window. A rebuilt root counts from this feed instead of asking the service again; the feed does not depend on the
/// account, only the hidden-category rule applied to it does, and that rule runs on every count.
@MainActor
final class QualityAlertsLaunchFeed {
    /// The one of the app, carried by the environments `AppEnvironment.make` builds; a root built without it (tests) gets its own.
    nonisolated static let shared = QualityAlertsLaunchFeed()

    /// The last feed read, nil until one was.
    private(set) var items: [AQFeedItem]?
    private var pending: Task<[AQFeedItem]?, Never>?

    /// An empty memo; nonisolated so the nonisolated `AppEnvironment.make` can name `shared`.
    nonisolated init() {}

    /// The kept feed, else the one `fetch` reads (nil when it failed), read once for every caller that asks while it runs. The
    /// read is not cancelled with a caller: another root may be waiting for it.
    func feed(fetch: @escaping @MainActor @Sendable () async -> [AQFeedItem]?) async -> [AQFeedItem]? {
        if let items { return items }
        if let pending { return await pending.value }
        let task = Task { await fetch() }
        pending = task
        let result = await task.value
        pending = nil
        // A feed kept meanwhile (the list was loaded) is newer than this read: it stays. A failed read is not kept, so the next
        // root asks again.
        if items == nil, let result { items = result }
        return items ?? result
    }

    /// Keeps `items`, read by the list or a count, for the next root.
    func keep(_ items: [AQFeedItem]) {
        self.items = items
    }
}
