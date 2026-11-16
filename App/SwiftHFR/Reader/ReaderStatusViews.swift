import SwiftUI

// Moved out of TopicReaderView.swift, which reached SwiftLint's `file_length` with the reader chrome of group R (#924).
/// What the reader shows over its web view while no page is on screen: the first load, its failure, an empty page.
struct ReaderStateOverlay: View {
    let model: TopicReaderModel
    let retry: () async -> Void
    let refresh: @MainActor () async -> Void

    var body: some View {
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

/// The confirmation of the last message-menu action, for two seconds.
struct ReaderMenuFeedbackBanner: View {
    let model: TopicReaderModel

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
