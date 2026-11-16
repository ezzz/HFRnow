import SwiftUI

// Port of HFRswift/Swift/MessagesView.swift (bottom bar :5639-5690, `pageChoiceMenuItems` and `pageChoiceMenuFinalTargets`
// :5019-5046) @ 87fe0d1c. Differences: SwiftHFR's "N / M" page bubble stays in the bar (when it shows is #820's); "Page …" asks
// in an alert, not a sheet; under a visible tab bar (Pro Max landscape, #649) the controls are a strip above it, as the
// lists' pager (#565). GAP-060.
/// Where the reader's bottom controls go, topic and private conversation alike (#836).
enum ReaderBottomBar {
    /// Where the controls go (#649): the system bottom bar of a reader beside a visible tab bar lands in the floating tab bar's
    /// frame (a Plus or Pro Max iPhone in landscape), so they become a strip inset above it, as `PagerPlacement` does for lists.
    enum Placement: Equatable { case bottomBar, inset }

    static func placement(rootHasTabBar: Bool, tabBar: Visibility) -> Placement {
        rootHasTabBar && tabBar != .hidden ? .inset : .bottomBar
    }
}

/// The reader's bottom controls as system bottom-bar items (Liquid Glass over the page; on the iPhone Duo cover screen they
/// move to the side with the system bars): ‹ ›, the page bubble and the reply button. Nothing under a visible tab bar:
/// `ReaderPageStrip` takes over there.
struct ReaderPageControls: ToolbarContent {
    let buttons: ReaderPageButtons
    let placement: ReaderBottomBar.Placement

    var body: some ToolbarContent {
        if placement == .bottomBar, let page = buttons.model.page {
            ToolbarItemGroup(placement: .bottomBar) {
                buttons.previous(page)
                buttons.next(page)
            }
            .visibilityPriority(.high)
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) { buttons.bubble(page) }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            if buttons.replySymbol != nil {
                ToolbarItem(placement: .bottomBar) { buttons.reply() }
                    .visibilityPriority(.high)
            }
        }
    }
}

/// The same controls as a glass strip above a visible tab bar (#649).
struct ReaderPageStrip: View {
    let buttons: ReaderPageButtons

    var body: some View {
        if let page = buttons.model.page {
            HStack {
                buttons.previous(page)
                buttons.next(page)
                Spacer()
                buttons.bubble(page)
                Spacer()
                if buttons.replySymbol != nil { buttons.reply() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }
}

/// The buttons of the bottom bar, built once for both placements.
@MainActor
struct ReaderPageButtons {
    let model: TopicReaderModel
    /// Opens the "Aller à la page" prompt.
    let askPage: () -> Void
    /// The reply button's symbol (`reply_button_behavior`); nil draws no button (hidden setting, logged out, no answer form).
    let replySymbol: String?

    /// Legacy ‹ opens the previous page at its last message (`navigateToPreviousPageFromBottomButton`, :4960-4964).
    func previous(_ page: ReaderPage) -> some View {
        Button("Page précédente", systemImage: "chevron.backward") {
            Task { await model.goToPage(page.currentPage - 1, atLastMessage: true) }
        }
        .disabled(!model.canGoToPrevious || model.isLoading || model.suspendsPageInteractions)
    }

    func next(_ page: ReaderPage) -> some View {
        Button("Page suivante", systemImage: "chevron.forward") {
            Task { await model.goToPage(page.currentPage + 1) }
        }
        .disabled(!model.canGoToNext || model.isLoading || model.suspendsPageInteractions)
    }

    func reply() -> some View {
        Button("Répondre", systemImage: replySymbol ?? "plus") { Task { await model.requestReply() } }
            .disabled(model.isLoadingQuote || model.suspendsPageInteractions)
    }

    /// The "N / M" bubble and its page menu; nothing to choose on a single page.
    func bubble(_ page: ReaderPage) -> some View {
        Menu {
            ReaderPageMenuItems(model: model, maxPage: page.maxPage, askPage: askPage)
        } label: {
            // A page loading shows here, as the shipped page bar did.
            if model.isLoading { ProgressView() } else { Text("\(page.currentPage) / \(page.maxPage)").monospacedDigit() }
        }
        // Under an open composer the page ignores its taps (#653): the menu stays shut.
        .disabled(page.maxPage <= 1 || model.suspendsPageInteractions)
        .accessibilityLabel("Page \(page.currentPage) sur \(page.maxPage)")
        .accessibilityHint("Choisir une page")
    }
}

/// "Actualiser" of the top bar.
struct ReaderRefreshButton: View {
    let model: TopicReaderModel
    let refresh: @MainActor () async -> Void

    var body: some View {
        Button { Task { await refresh() } } label: { Label("Actualiser", systemImage: "arrow.clockwise") }
            .disabled(model.isLoading || model.suspendsPageInteractions)
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
        case page(Int), ask, lastPost

        /// Legacy's labels (`pageChoiceMenuItems`, :5029-5046 @ 87fe0d1c): numbers, not "Première page" / "Dernière page",
        /// so each entry says where it leads (#821).
        var title: String {
            switch self {
            case .page(let number): "Page \(number)"
            case .ask: "Page …"
            case .lastPost: "Dernier post"
            }
        }
    }

    /// Where an item goes; nil for the prompt. "Page N" opens the top of the page, "Dernier post" the last page's last message.
    static func destination(of item: Item, maxPage: Int) -> (page: Int, atLastMessage: Bool)? {
        switch item {
        case .page(let number): (number, false)
        case .ask: nil
        case .lastPost: (maxPage, true)
        }
    }

    /// Legacy order: page 1, the prompt, the last three pages after page 1, the last post; none on a single page.
    static func items(maxPage: Int) -> [Item] {
        guard maxPage > 1 else { return [] }
        return [.page(1), .ask] + finalTargets(maxPage: maxPage).map(Item.page) + [.lastPost]
    }

    /// The last three pages after page 1, without repeats (legacy `pageChoiceMenuFinalTargets`, `MessagesView.swift:5019-5026`
    /// @ 87fe0d1c): `[3, 4, 5]` for 5 pages, `[2]` for 2, none for a single page.
    static func finalTargets(maxPage: Int) -> [Int] {
        guard maxPage > 1 else { return [] }
        return Array(max(2, maxPage - 2)...maxPage)
    }
}
