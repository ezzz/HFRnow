import SwiftUI

// Moved out of TopicReaderView.swift, which reached SwiftLint's `file_length` with the reader chrome of group R (#924).
/// What the reader shows over its web view while no page is on screen: the first load, its failure, an empty page.
struct ReaderStateOverlay: View {
    let model: TopicReaderModel
    let retry: () async -> Void
    let refresh: @MainActor () async -> Void

    var body: some View {
        // A base that always exists and fills the space with no minimum: over a shown page `content` builds no view, and the
        // icons need something to hang on. It takes no touch, so the page under it keeps them.
        Color.clear
            .allowsHitTesting(false)
            .overlay { content }
            // The pulls past the page's top and end (#1207): the end's above the floating bar, never in the way of a touch.
            // Overlays, so they never size the page: stacked beside it, the end's 96 pt gave the reader a minimum height of
            // about 135 pt, which pushed the docked composer behind the keyboard and the page under the bars (#1285, #1286).
            .overlay(alignment: .top) {
                PullRefreshIcon(progress: model.pullTop, isRefreshing: model.pulledEdge == .top)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                PullRefreshIcon(progress: model.pullBottom, isRefreshing: model.pulledEdge == .bottom)
                    .padding(.bottom, 96)
                    .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.page == nil {
            ScreenStateView(
                state: ScreenLoadState(error: model.error, isLoading: true), loadingLabel: "Chargement des messages", retry: retry
            )
        } else if let page = model.page, page.messages.isEmpty {
            EmptyStateView(
                title: "Aucun message", symbol: "text.bubble", message: page.notice ?? "Cette page ne contient aucun message.",
                refresh: refresh
            )
        } else if !model.hasShownDocument {
            // The web view could not show the page (issue #566): a retry, never an endless spinner.
            ScreenStateView(
                state: ScreenLoadState(error: model.error, isLoading: true), loadingLabel: "Chargement des messages", retry: retry
            )
        }
    }
}

/// A screen whose message menus confirm their actions with a short text: the reader and the filtered posts (LOT-159).
@MainActor
protocol MenuFeedbackShowing: AnyObject {
    /// The confirmation on screen, nil when none.
    var menuFeedback: String? { get }
    /// Bumped by each confirmation, so a repeated text is shown again.
    var menuFeedbackSerial: Int { get }
    /// Hides the confirmation `serial` stands for, unless a newer one replaced it.
    func clearMenuFeedback(serial: Int)
}

extension TopicReaderModel: MenuFeedbackShowing {}

/// The confirmation of the last message-menu action, for two seconds.
struct ReaderMenuFeedbackBanner: View {
    let model: any MenuFeedbackShowing

    var body: some View {
        if let feedback = model.menuFeedback {
            Text(feedback)
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 8)
                .task(id: model.menuFeedbackSerial) { [serial = model.menuFeedbackSerial] in
                    // A cancelled sleep (a newer confirmation, the view going away) must not clear anything.
                    do {
                        try await Task.sleep(for: .seconds(2))
                        model.clearMenuFeedback(serial: serial)
                    } catch {}
                }
        }
    }
}
