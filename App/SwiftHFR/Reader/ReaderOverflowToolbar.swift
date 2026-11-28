import HFRModels
import SwiftUI

// Port of HFRswift/Swift/MessagesView.swift (the toolbar `Menu`, :5575-5604) @ 87fe0d1c. Differences: legacy's menu is Rechercher,
// Répondre, a divider, the page items; SwiftHFR's overflow also holds Hors ligne and Filtrer (secondary actions of the system
// overflow). Répondre is a bottom-bar button (`ReaderPageControls`, LOT-186 D2), so it is in the overflow only when « Bouton + »
// is « Pas d'icône » and the bar has none (#1452, operator decision 2026-11-28): the one plain reply path then. GAP-102.
/// What the reader's system "…" overflow holds and in which order: legacy puts Rechercher first and the page items last.
enum ReaderOverflow {
    enum Entry: Hashable, Sendable { case search, reply, offline, filter, pages }

    /// The present entries, in menu order (#645, #1452): Rechercher, Répondre, then the rest. Pure so the order is pinned by a test.
    static func entries(search: Bool, reply: Bool = false, offline: Bool, filter: Bool, pages: Bool) -> [Entry] {
        let order: [(Entry, Bool)] = [
            (.search, search), (.reply, reply), (.offline, offline), (.filter, filter), (.pages, pages)
        ]
        return order.filter(\.1).map(\.0)
    }

    /// The overflow's « Répondre »: whether it is offered and whether a quote fetch makes it busy (as the bar's button).
    struct ReplyItem {
        let offered: Bool
        let busy: Bool
        let action: () -> Void
    }

    /// « Répondre » is in the overflow only when the bottom bar has no reply button (« Bouton + » = « Pas d'icône »), and then
    /// only with an account and an answer form, as the bar's button (`replySymbol`), and not under an open composer.
    static func offersReply(behavior: ReplyButtonBehavior, hasComposer: Bool, hasReplyTarget: Bool, suspended: Bool) -> Bool {
        behavior == .hidden && hasComposer && hasReplyTarget && !suspended
    }
}

extension TopicReaderModel {
    /// The overflow's reply item: the same `requestReply()` as the bottom-bar button, disabled while a quote loads.
    func overflowReply(behavior: ReplyButtonBehavior, hasComposer: Bool) -> ReaderOverflow.ReplyItem {
        ReaderOverflow.ReplyItem(
            offered: ReaderOverflow.offersReply(
                behavior: behavior, hasComposer: hasComposer, hasReplyTarget: replyTarget != nil, suspended: suspendsPageInteractions),
            busy: isLoadingQuote, action: { Task { await self.requestReply() } })
    }
}

/// The reader's overflow items in one `.toolbar`: separate `.toolbar` modifiers are ordered by the system in its own way
/// (the outermost first), so one content value declares the order and only that order.
struct ReaderOverflowToolbar: ToolbarContent {
    let entries: [ReaderOverflow.Entry]
    let search: () -> Void
    let reply: ReaderOverflow.ReplyItem
    let offline: AnyView
    let filter: () -> Void
    let filterIsBusy: Bool
    let pages: AnyView

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        ForEach(entries, id: \.self) { entry in
            switch entry {
            case .search:
                ToolbarItem(placement: .secondaryAction) {
                    Button(action: search) { Label("Rechercher dans le sujet", systemImage: "magnifyingglass") }
                }
            case .reply:
                ToolbarItem(placement: .secondaryAction) {
                    Button(action: reply.action) { Label("Répondre", systemImage: "square.and.pencil") }
                        .disabled(reply.busy)
                }
            case .offline:
                ToolbarItem(placement: .secondaryAction) { offline }
            case .filter:
                ToolbarItem(placement: .secondaryAction) {
                    Button(action: filter) { Label("Filtrer les posts", systemImage: "line.3.horizontal.decrease") }
                        .disabled(filterIsBusy)
                }
            case .pages:
                // A Section, so the separator before the page items is explicit (legacy `Divider()`, :4718-4720 @ 2440d79).
                ToolbarItemGroup(placement: .secondaryAction) { Section { pages } }
            }
        }
    }
}
