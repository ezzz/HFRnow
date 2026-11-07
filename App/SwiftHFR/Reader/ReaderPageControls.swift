import SwiftUI

// Port of HFRswift/Swift/MessagesView.swift (MessagesView: bottom toolbar, `bottomPreviousPageButton`,
// `bottomNextPageButton`, `pageChoiceMenuItems`, `pageChoiceMenuFinalTargets`) @ 2440d79 (lines 4184-4236, 4756-4800).
// Differences: the page choices are a "N / M" menu in the bottom bar instead of the top "…" menu, which the iPhone Duo HIG
// reserves for overflow; "Page…" asks in an alert, not a sheet; the reply button stays in landscape (the system moves
// it to the overflow menu when space runs out); no bottom refresh button, "Actualiser" stays in the top bar (GAP-060,
// UXD-10, LOT-186).
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

    /// Legacy `pageChoiceMenuItems`: page 1, "Page…", the last pages and the last post; nothing to choose on a single page.
    private func pageMenu(_ page: ReaderPage) -> some View {
        Menu {
            Button("Page 1") { Task { await model.goToPage(1) } }
            Button("Page…", action: askPage)
            ForEach(ReaderPageMenu.finalTargets(maxPage: page.maxPage), id: \.self) { target in
                Button("Page \(target)") { Task { await model.goToPage(target) } }
            }
            Button("Dernier post") { Task { await model.goToPage(page.maxPage, atLastMessage: true) } }
        } label: {
            // A page loading shows here, as the shipped page bar did.
            if model.isLoading { ProgressView() } else { Text("\(page.currentPage) / \(page.maxPage)").monospacedDigit() }
        }
        .disabled(page.maxPage <= 1)
        .accessibilityLabel("Page \(page.currentPage) sur \(page.maxPage)")
        .accessibilityHint("Choisir une page")
    }
}

/// The page choices of the bottom bar's menu.
enum ReaderPageMenu {
    /// The last three pages after page 1, without repeats (legacy `pageChoiceMenuFinalTargets`, `MessagesView.swift:4206-4213`
    /// @ 2440d79): `[3, 4, 5]` for 5 pages, `[2]` for 2, none for a single page.
    static func finalTargets(maxPage: Int) -> [Int] {
        guard maxPage > 1 else { return [] }
        return Array(max(2, maxPage - 2)...maxPage)
    }
}
