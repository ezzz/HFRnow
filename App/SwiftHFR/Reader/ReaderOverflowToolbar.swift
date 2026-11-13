import SwiftUI

// Port of HFRswift/Swift/MessagesView.swift (the toolbar `Menu`, :5589-5604) @ 87fe0d1c. Differences: Rechercher, Hors ligne
// and Filtrer are secondary actions of the system overflow, and "Répondre" lives in the bottom bar (GAP rows unchanged).
/// What the reader's system "…" overflow holds and in which order: legacy puts Rechercher first and the page items last.
enum ReaderOverflow {
    enum Entry: Hashable, Sendable { case search, offline, filter, pages }

    /// The present entries, in menu order (#645). Pure so the order is pinned by a test.
    static func entries(search: Bool, offline: Bool, filter: Bool, pages: Bool) -> [Entry] {
        let order: [(Entry, Bool)] = [(.search, search), (.offline, offline), (.filter, filter), (.pages, pages)]
        return order.filter(\.1).map(\.0)
    }
}

/// The reader's overflow items in one `.toolbar`: separate `.toolbar` modifiers are ordered by the system in its own way
/// (the outermost first), so one content value declares the order and only that order.
struct ReaderOverflowToolbar: ToolbarContent {
    let entries: [ReaderOverflow.Entry]
    let search: () -> Void
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
            case .offline:
                ToolbarItem(placement: .secondaryAction) { offline }
            case .filter:
                ToolbarItem(placement: .secondaryAction) {
                    Button(action: filter) { Label("Filtrer les posts", systemImage: "line.3.horizontal.decrease") }
                        .disabled(filterIsBusy)
                }
            case .pages:
                // A Section, so the separator before the page items is explicit (legacy `Divider()`, :4718-4720).
                ToolbarItemGroup(placement: .secondaryAction) { Section { pages } }
            }
        }
    }
}
