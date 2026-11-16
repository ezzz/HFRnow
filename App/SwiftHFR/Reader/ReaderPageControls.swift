import SwiftUI

// Port of HFRswift/Swift/MessagesView.swift (bottom bar :5639-5690, `shouldShowBottomRefreshButton` and
// `shouldPromoteBottomNextPageButton` :4972-4978, `pageChoiceMenuItems` and `pageChoiceMenuFinalTargets` :5019-5046,
// `topicBottomBarButtonStyle` :7372-7386) @ 87fe0d1c. Differences: the "N / M" page bubble of SwiftHFR is kept, but only at the
// end of the page, with the bottom refresh (operator, #820, 2026-11-15); the top refresh stays and the bottom one is the same
// button (`ReaderRefreshButton`); VoiceOver keeps the bubble at all times; "Page …" asks in an alert, not a sheet; under a
// visible tab bar (Pro Max landscape, #649) the controls are a strip above it, as the lists' pager (#565); at the end of a page the
// bubble is its own pill between ‹ › and refresh + reply (operator, #961). GAP-060.
/// The reader's bottom bar, topic and private conversation alike (#836): ‹ ›, then at the end of the page the page bubble and
/// the refresh, and the reply button; three pills (#961): ‹ ›, the bubble alone, refresh + reply. Legacy promotes › at the end
/// of a page that is not the last, and the refresh at the end of the last page.
enum ReaderBottomBar {
    /// What the bar shows for one scroll position.
    struct State: Equatable {
        var showsPageBubble: Bool
        var showsRefresh: Bool
        var promotesNext: Bool
        var promotesRefresh: Bool
        /// The reply button is drawn (setting, login and answer form allow it).
        var showsReply = true

        /// The three pills, left to right (#961): ‹ › on the left, the "N / M" bubble alone and centred, refresh and reply on
        /// the right. An empty pill is not drawn, and the bubble keeps its own pill with or without the others.
        var leading: [Control] { [.previous, .next] }
        var centre: [Control] { showsPageBubble ? [.pageBubble] : [] }
        var trailing: [Control] { (showsRefresh ? [.refresh] : []) + (showsReply ? [.reply] : []) }
    }

    /// One control of the bar.
    enum Control: Hashable { case previous, next, pageBubble, refresh, reply }

    /// `atPageEnd`: the page's end is on screen (legacy `isWebContentAtBottom`). VoiceOver users get the bubble everywhere:
    /// hiding it is visual only (#820).
    static func state(currentPage: Int, maxPage: Int, atPageEnd: Bool, voiceOver: Bool, showsReply: Bool = true) -> State {
        let isLastPage = currentPage >= maxPage
        return State(
            showsPageBubble: atPageEnd || voiceOver, showsRefresh: atPageEnd,
            promotesNext: atPageEnd && !isLastPage, promotesRefresh: atPageEnd && isLastPage,
            showsReply: showsReply
        )
    }

    /// Where the controls go (#649): the system bottom bar of a reader beside a visible tab bar lands in the floating tab bar's
    /// frame (a Plus or Pro Max iPhone in landscape), so they become a strip inset above it, as `PagerPlacement` does for lists.
    enum Placement: Equatable { case bottomBar, inset }

    static func placement(rootHasTabBar: Bool, tabBar: Visibility) -> Placement {
        rootHasTabBar && tabBar != .hidden ? .inset : .bottomBar
    }
}

/// The reader's bottom controls as system bottom-bar items (Liquid Glass over the page; on the iPhone Duo cover screen they
/// move to the side with the system bars). Nothing under a visible tab bar: `ReaderPageStrip` takes over there.
struct ReaderPageControls: ToolbarContent {
    let buttons: ReaderPageButtons
    let placement: ReaderBottomBar.Placement

    var body: some ToolbarContent {
        if placement == .bottomBar, let page = buttons.model.page {
            let state = buttons.state(page)
            ToolbarItemGroup(placement: .bottomBar) {
                ForEach(state.leading, id: \.self) { buttons.view(for: $0, page: page, state: state) }
            }
            .visibilityPriority(.high)
            // Flexible spacers split the glass into one pill per group (#961). The system bar centres the bubble between its two
            // neighbours, not on the screen: it is on the screen's centre only while both side pills are as wide (end of a page,
            // logged in). The strip below always is.
            ToolbarSpacer(.flexible, placement: .bottomBar)
            if !state.centre.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    ForEach(state.centre, id: \.self) { buttons.view(for: $0, page: page, state: state) }
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
            }
            if !state.trailing.isEmpty {
                // High priority for the pill as a whole: refresh and reply are the last to be dropped when the bar is short.
                ToolbarItemGroup(placement: .bottomBar) {
                    ForEach(state.trailing, id: \.self) { buttons.view(for: $0, page: page, state: state) }
                }
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
            let state = buttons.state(page)
            HStack {
                HStack {
                    ForEach(state.leading, id: \.self) { buttons.view(for: $0, page: page, state: state) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(state.centre, id: \.self) { buttons.view(for: $0, page: page, state: state) }
                HStack {
                    ForEach(state.trailing, id: \.self) { buttons.view(for: $0, page: page, state: state) }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
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
    /// The page's end is on screen (`reader.js` reports it).
    let atPageEnd: Bool
    let voiceOver: Bool
    /// Opens the "Page numéro" sheet.
    let askPage: () -> Void
    /// The reply button's symbol (`reply_button_behavior`); nil draws no button (hidden setting, logged out, no answer form).
    let replySymbol: String?
    /// The reader's one refresh, also behind the top bar's button.
    let refresh: @MainActor () async -> Void

    func state(_ page: ReaderPage) -> ReaderBottomBar.State {
        ReaderBottomBar.state(
            currentPage: page.currentPage, maxPage: page.maxPage, atPageEnd: atPageEnd, voiceOver: voiceOver,
            showsReply: replySymbol != nil
        )
    }

    /// One control of the bar: both placements draw their pills from the state's lists (#961).
    @ViewBuilder
    func view(for control: ReaderBottomBar.Control, page: ReaderPage, state: ReaderBottomBar.State) -> some View {
        switch control {
        case .previous: previous(page)
        case .next: next(page, prominent: state.promotesNext)
        case .pageBubble: bubble(page)
        case .refresh: refreshButton(prominent: state.promotesRefresh)
        case .reply: reply()
        }
    }

    /// Legacy ‹ opens the previous page at its last message (`navigateToPreviousPageFromBottomButton`, :4960-4964).
    func previous(_ page: ReaderPage) -> some View {
        Button("Page précédente", systemImage: "chevron.backward") {
            Task { await model.goToPage(page.currentPage - 1, atLastMessage: true) }
        }
        .disabled(!model.canGoToPrevious || model.isLoading || model.suspendsPageInteractions)
    }

    func next(_ page: ReaderPage, prominent: Bool) -> some View {
        Button("Page suivante", systemImage: "chevron.forward") {
            Task { await model.goToPage(page.currentPage + 1) }
        }
        .readerBarProminence(prominent)
        .disabled(!model.canGoToNext || model.isLoading || model.suspendsPageInteractions)
    }

    func refreshButton(prominent: Bool) -> some View {
        ReaderRefreshButton(model: model, refresh: refresh).readerBarProminence(prominent)
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

/// "Actualiser": one button for the top bar and the end of the page (#820), so both run the same refresh.
struct ReaderRefreshButton: View {
    let model: TopicReaderModel
    let refresh: @MainActor () async -> Void

    var body: some View {
        Button { Task { await refresh() } } label: { Label("Actualiser", systemImage: "arrow.clockwise") }
            .disabled(model.isLoading || model.suspendsPageInteractions)
    }
}

extension View {
    /// Legacy `topicBottomBarButtonStyle(isProminent:)`: the next useful action is drawn prominent.
    @ViewBuilder
    func readerBarProminence(_ prominent: Bool) -> some View {
        if prominent { buttonStyle(.glassProminent) } else { self }
    }
}

/// The page items shared by the bottom "N / M" menu and the top "…" overflow (#582): one list, so the two cannot drift.
struct ReaderPageMenuItems: View {
    let model: TopicReaderModel
    let maxPage: Int
    /// Opens the "Page numéro" sheet.
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
