import SwiftUI

// Moved out of TopicReaderView.swift, which reached SwiftLint's `file_length` with the reader chrome of group R (#924).
/// What the reader shows over its web view while no page is on screen: the first load, its failure, an empty page.
struct ReaderStateOverlay: View {
    let model: TopicReaderModel
    let retry: () async -> Void
    let refresh: @MainActor () async -> Void

    var body: some View {
        ZStack {
            content
            // The pulls past the page's top and end (#1207): the end's above the floating bar, never in the way of a touch.
            PullRefreshIcon(progress: model.pullTop, isRefreshing: model.pulledEdge == .top)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
            PullRefreshIcon(progress: model.pullBottom, isRefreshing: model.pulledEdge == .bottom)
                .padding(.bottom, 96)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.page == nil {
            if let error = model.error {
                LoadFailureView(error: error, retry: retry)
            } else {
                ProgressView("Chargement des messages")
            }
        } else if let page = model.page, page.messages.isEmpty {
            ContentUnavailableView {
                Label("Aucun message", systemImage: "text.bubble")
            } description: {
                Text(page.notice ?? "Cette page ne contient aucun message.")
            } actions: {
                Button("Actualiser") { Task { await refresh() } }
            }
        } else if !model.hasShownDocument {
            // The web view could not show the page (issue #566): a retry, never an endless spinner.
            if let error = model.error {
                LoadFailureView(error: error, retry: retry)
            } else {
                ProgressView("Chargement des messages")
            }
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
