import SwiftUI

// Port of HFRswift/Swift/MessagesView.swift (MessagesView: bottom toolbar, `bottomPreviousPageButton`,
// `bottomNextPageButton`, `pageChoiceMenuItems`, `pageChoiceMenuFinalTargets`) @ 2440d79 (lines 4184-4236, 4756-4800).
// Differences: the page choices are in a "N / M" menu in the bottom bar and in the top "…" overflow (#582), as one list
// (`ReaderPageMenuItems`), with the labels "Première page", "Aller à la page…" and a new "Dernière page" that replaces
// the last "Page N" (LOT-186 D1, operator 2026-11-07); "Aller à la page…" asks in an alert, not a sheet; the reply button
// stays in landscape (the system moves it to the overflow menu when space runs out); no bottom refresh button, "Actualiser"
// stays in the top bar (GAP-060, UXD-10, LOT-186).
/// The reader's bottom bar (LOT-186, #428): ‹ › as one group, the page menu, and the reply button. System toolbar items, so
/// they float as Liquid Glass over the page, and on the iPhone Duo cover screen they move to the side with the system bars.
struct ReaderPageControls: ToolbarContent {
    let model: TopicReaderModel
    /// Opens the "Aller à la page" prompt.
    let askPage: () -> Void
    /// The reply button's symbol (`reply_button_behavior`); nil draws no button (hidden setting, logged out, no answer form).
    let replySymbol: String?

    var body: some ToolbarContent {
        if let page = model.page {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Page précédente", systemImage: "chevron.backward") {
                    Task { await model.goToPage(page.currentPage - 1, atLastMessage: true) }
                }
                .disabled(!model.canGoToPrevious || model.isLoading)
                Button("Page suivante", systemImage: "chevron.forward") {
                    Task { await model.goToPage(page.currentPage + 1) }
                }
                .disabled(!model.canGoToNext || model.isLoading)
            }
            .visibilityPriority(.high)
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) { pageMenu(page) }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            if let replySymbol {
                ToolbarItem(placement: .bottomBar) {
                    Button("Répondre", systemImage: replySymbol) { Task { await model.requestReply() } }
                        .disabled(model.isLoadingQuote)
                }
                .visibilityPriority(.high)
            }
        }
    }

    /// Legacy `pageChoiceMenuItems`; nothing to choose on a single page.
    private func pageMenu(_ page: ReaderPage) -> some View {
        Menu {
            ReaderPageMenuItems(model: model, maxPage: page.maxPage, askPage: askPage)
        } label: {
            // A page loading shows here, as the shipped page bar did.
            if model.isLoading { ProgressView() } else { Text("\(page.currentPage) / \(page.maxPage)").monospacedDigit() }
        }
        .disabled(page.maxPage <= 1)
        .accessibilityLabel("Page \(page.currentPage) sur \(page.maxPage)")
        .accessibilityHint("Choisir une page")
    }
}

/// The page items shared by the bottom "N / M" menu and the top "…" overflow (#582): one list, so the two cannot drift.
struct ReaderPageMenuItems: View {
    let model: TopicReaderModel
    let maxPage: Int
    /// Opens the "Aller à la page" prompt.
    let askPage: () -> Void

    var body: some View {
        ForEach(ReaderPageMenu.items(maxPage: maxPage), id: \.self) { item in
            Button(item.title) {
                if let destination = ReaderPageMenu.destination(of: item, maxPage: maxPage) {
                    Task { await model.goToPage(destination.page, atLastMessage: destination.atLastMessage) }
                } else {
                    askPage()
                }
            }
            .disabled(model.isLoading)
        }
    }
}

/// The page choices of the page menus.
enum ReaderPageMenu {
    /// One entry of the menu.
    enum Item: Hashable {
        case first, ask, page(Int), last, lastPost

        /// Wording: "Aller à la page…" / "Première page" / "Dernière page" as the issue asks (legacy: "Page ...", "Page 1");
        /// "Page N" and "Dernier post" are legacy's.
        var title: String {
            switch self {
            case .first: "Première page"
            case .ask: "Aller à la page…"
            case .page(let number): "Page \(number)"
            case .last: "Dernière page"
            case .lastPost: "Dernier post"
            }
        }
    }

    /// Where an item goes; nil for the prompt. "Dernière page" opens the top of the last page, "Dernier post" its last message.
    static func destination(of item: Item, maxPage: Int) -> (page: Int, atLastMessage: Bool)? {
        switch item {
        case .first: (1, false)
        case .ask: nil
        case .page(let number): (number, false)
        case .last: (maxPage, false)
        case .lastPost: (maxPage, true)
        }
    }

    /// Legacy `pageChoiceMenuItems` order: first page, prompt, last pages, last page, last post; none on a single page.
    /// "Dernière page" stands for legacy's last "Page N", so that one is dropped from the targets (no repeat).
    static func items(maxPage: Int) -> [Item] {
        guard maxPage > 1 else { return [] }
        return [.first, .ask] + finalTargets(maxPage: maxPage).filter { $0 != maxPage }.map(Item.page) + [.last, .lastPost]
    }

    /// The last three pages after page 1, without repeats (legacy `pageChoiceMenuFinalTargets`, `MessagesView.swift:4206-4213`
    /// @ 2440d79): `[3, 4, 5]` for 5 pages, `[2]` for 2, none for a single page.
    static func finalTargets(maxPage: Int) -> [Int] {
        guard maxPage > 1 else { return [] }
        return Array(max(2, maxPage - 2)...maxPage)
    }
}
