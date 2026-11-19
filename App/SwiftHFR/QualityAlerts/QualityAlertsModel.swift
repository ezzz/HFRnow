import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRStorage
import Observation

// Port of HFRswift/Swift/AQPlusView.swift (AQPlusViewModel, AQBadgeCheckService, AQUnreadCounter) @ 87fe0d1c. Differences: the
// count is recomputed from the feed at each root build instead of read back from `nb_aq` (B23); a request that started before the
// list was shown is dropped by a ticket, not by comparing dates; an item with an unreadable date is not new (LOT-055); the hidden
// category comes from `ForumVisibility` (Q-7); a failed or unreadable answer is a failure state, not an empty list.
/// The Alertes Qualitay list and the "new since" count of the Plus tab: one model per root, shared by the badge and the screen.
///
/// The count is the number of items published at or after the last time the list was shown (`last_check_aq`, default 2010-01-01),
/// after the hidden category is removed, so the badge never counts what the list would not show. Showing the list sets the last
/// check to now and the count to 0; a count request that started before that, or while the list was loading, cannot bring the
/// badge back (no phantom badge).
@MainActor
@Observable
final class QualityAlertsModel {
    /// One row of the list.
    struct Row: Identifiable, Hashable, Sendable {
        /// The feed item.
        let item: AQFeedItem
        /// Published at or after the last time the list was shown (bold row, legacy `isNew`).
        let isNew: Bool
        /// The reader target of the reported message: its page and its anchor are kept (issues #105, #106); nil when the link is
        /// not a topic link of the forum.
        let target: ReaderTarget?

        var id: String { item.id }

        /// The topic title as lists show it (legacy abbreviates "topic unique" and its spellings).
        var title: String { TopicTitle.displayed(item.topicTitle) }
    }

    /// Why the list could not be shown.
    enum Failure: Equatable, Sendable {
        /// The build carries no usable AQ address.
        case unavailable
        /// No connection.
        case offline
        /// The service did not answer in time.
        case timedOut
        /// Any other failure, including an answer that is not the feed.
        case other

        init(_ error: AQError) {
            switch error {
            case .network(.offline): self = .offline
            case .network(.timedOut): self = .timedOut
            default: self = .other
            }
        }

        /// Short title, in French.
        var title: String {
            switch self {
            case .unavailable: "Alertes Qualitay indisponibles"
            case .offline: "Pas de connexion"
            case .timedOut: "Le service ne répond pas"
            case .other: "Chargement impossible"
            }
        }

        /// What happened, in French.
        var detail: String {
            switch self {
            case .unavailable: "Cette version n'a pas d'adresse pour le service des Alertes Qualitay."
            case .offline: "Vérifiez votre connexion puis réessayez."
            case .timedOut: "Le service des Alertes Qualitay n'a pas répondu à temps. Réessayez dans un moment."
            case .other: "La liste des Alertes Qualitay n'a pas pu être lue. Réessayez dans un moment."
            }
        }
    }

    /// The date before which nothing was ever checked (legacy default `Tue, 1 JAN 2010`, `AQTableViewController.m:303`).
    static let neverChecked = Date(timeIntervalSince1970: 1_262_304_000)

    /// The rows of the list, hidden category removed; empty until a load succeeded.
    private(set) var rows: [Row] = []
    /// Items newer than the last time the list was shown: the Plus badge.
    private(set) var unreadCount = 0
    /// The list is loading.
    private(set) var isLoading = false
    /// Why the last load failed; the rows of an earlier success stay on screen.
    private(set) var failure: Failure?
    /// A load has ended, in success or failure (the empty state is only true after it).
    private(set) var hasLoaded = false

    @ObservationIgnored private let source: (any QualityAlertsSource)?
    @ObservationIgnored private let visibility: ForumVisibility
    @ObservationIgnored private let isLoggedIn: @Sendable () async -> Bool
    @ObservationIgnored private let accountName: @Sendable () async -> String?
    @ObservationIgnored private let store: any SettingsStore
    @ObservationIgnored private let now: @Sendable () -> Date
    /// Taken by every request that may change `unreadCount`; only the newest one applies.
    @ObservationIgnored private var countTicket = 0
    @ObservationIgnored private var loadTicket = 0

    /// Creates the model; `source` is nil when the build carries no AQ address.
    init(
        source: (any QualityAlertsSource)?, visibility: ForumVisibility = ForumVisibility(),
        isLoggedIn: @escaping @Sendable () async -> Bool, accountName: @escaping @Sendable () async -> String?,
        store: any SettingsStore, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.visibility = visibility
        self.isLoggedIn = isLoggedIn
        self.accountName = accountName
        self.store = store
        self.now = now
    }

    /// The last time the list was shown.
    var lastCheck: Date { store.value(for: SettingKey.aqLastCheck) ?? Self.neverChecked }

    /// The count at launch: waits `delay` (legacy 3 s after the main window, `MainWindow.swift:1178-1192` @ 2440d79), then fetches
    /// the feed, logged out too, and sets the badge. A cancellation during the wait fetches nothing.
    func checkAtLaunch(
        after delay: Duration = .seconds(3), sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async {
        do { try await sleep(delay) } catch { return }
        await refreshCount()
    }

    /// Fetches the feed and sets the badge, without touching the list or the last check. A failed answer says nothing and keeps the
    /// count (legacy's silent `catch`); an answer that is overtaken by a newer count request or by a load is dropped.
    func refreshCount() async {
        guard let source else { return }
        countTicket += 1
        let ticket = countTicket
        let lastCheck = self.lastCheck
        guard let items = try? await source.feed() else { return }
        let visible = await visibleItems(items)
        guard ticket == countTicket else { return }
        unreadCount = AQClient.newCount(in: visible, since: lastCheck)
    }

    /// Loads the list, then marks it seen: the last check becomes now and the badge 0, after the rows are set (a failure marks
    /// nothing). A load that is overtaken by a newer one is dropped.
    func load() async {
        guard let source else {
            failure = .unavailable
            hasLoaded = true
            return
        }
        // A count request already in flight predates this visit: it must not bring the badge back.
        countTicket += 1
        loadTicket += 1
        let ticket = loadTicket
        let lastCheck = self.lastCheck
        isLoading = true
        do throws(AQError) {
            // A cancellation nobody asked for is asked once more (#1191).
            let items = try await retryingUnrequestedCancellation(isCancellation: { $0 == .network(.cancelled) }) {
                () async throws(AQError) -> [AQFeedItem] in try await source.feed()
            }
            let visible = await visibleItems(items)
            guard ticket == loadTicket else { return }
            rows = visible.map { Row(item: $0, isNew: AQClient.isNew($0, since: lastCheck), target: Self.target(of: $0)) }
            failure = nil
            store.set(now(), for: SettingKey.aqLastCheck)
            // A count that started while this load ran read the old last check and may land after it: drop it too.
            countTicket += 1
            unreadCount = 0
        } catch {
            guard ticket == loadTicket else { return }
            if case .network(.cancelled) = error, Task.isCancelled {
                // The screen went away (a tab switch cancels its task): not a failure and not an empty list. Nothing was learned,
                // so `hasLoaded` stays as it was and the screen asks again when it comes back. A cancellation nobody asked for
                // came twice: it ends the load as a failure below, never as "Chargement…" for ever (#1191).
                isLoading = false
                return
            }
            failure = Failure(error)
        }
        isLoading = false
        hasLoaded = true
    }

    /// `items` without the hidden category when the viewer is logged out or is the review account (Q-7).
    private func visibleItems(_ items: [AQFeedItem]) async -> [AQFeedItem] {
        guard visibility.hidesCategory(isLoggedIn: await isLoggedIn(), accountName: await accountName()) else { return items }
        return items.filter { Self.category(of: $0.link) != visibility.hiddenCategory }
    }

    /// The `cat` parameter of a reported message's link; the canonical `/hfr/…-sujet_N_P.htm` links carry none.
    static func category(of link: URL) -> CategoryID? {
        URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "cat" }?.value.flatMap(CategoryID.init(queryValue:))
    }

    private static func target(of item: AQFeedItem) -> ReaderTarget? {
        ReaderTarget(link: item.link.absoluteString)
    }
}
