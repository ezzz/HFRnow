import SwiftUI

/// Where "Marquer comme non lu" stands in a reader.
enum MarkUnreadState: Equatable, Sendable {
    /// Nothing running: the entry can be picked.
    case idle
    /// The write left or is about to: the entry waits for its answer, so a second tap sends nothing.
    case sending
    /// The write failed or was not confirmed: `reason` says why, in French, and the entry can be picked again.
    case failed(String)
}

/// Who hears how "Marquer comme non lu" ended: the conversation's list.
typealias MarkUnreadHost = @MainActor (TopicFlagOutcome) async -> Void

// Port of Classes/OnlineMessagesTableViewController.m (markUnread, :888-913, and its action-sheet entry, :805-807) @ 2440d79.
// Differences: GAP-116; the session is checked first and only HFR's own sentence is a success (LOT-058), a failure is shown
// (legacy dropped it and stayed), HFR's sentence is shown over the list. The Swift layer's reader menu has no such entry
// (`MessagesView.swift:4694-4722`).
extension TopicReaderModel {
    /// Sends the page's `nonlu.php` link once and tells `host`. HFR's confirmation goes to the list that closes this reader,
    /// or shows here when no list hosts it; a failure stays here and is never resent, the member picks the entry again.
    func markUnread(with actions: TopicFlagActions, host: MarkUnreadHost?) async {
        guard markUnreadState != .sending, let link = page?.markUnreadURL else { return }
        markUnreadState = .sending
        let outcome = await actions.markUnread(link: link)
        switch outcome {
        case .done(let message):
            markUnreadState = .idle
            if host == nil { showMenuFeedback(message) }
        case .failed(let reason):
            markUnreadState = .failed(reason)
        }
        await host?(outcome)
    }

    /// The failure was read.
    func clearMarkUnreadFailure() {
        if case .failed = markUnreadState { markUnreadState = .idle }
    }
}

/// The reader's "Marquer comme non lu" entry (LOT-127), offered when the page has HFR's own link and an account is current
/// (`actions` is nil logged out and in the offline reader), and its failure alert.
struct ReaderMarkUnreadFlow: ViewModifier {
    let model: TopicReaderModel
    let actions: TopicFlagActions?
    let host: MarkUnreadHost?

    func body(content: Content) -> some View {
        content
            .toolbar {
                if let actions, model.page?.markUnreadURL != nil {
                    ToolbarItem(placement: .secondaryAction) {
                        Button { Task { await model.markUnread(with: actions, host: host) } } label: {
                            Label("Marquer comme non lu", systemImage: "envelope.badge")
                        }
                        .disabled(model.markUnreadState == .sending)
                    }
                }
            }
            .alert("Action impossible", isPresented: failureShown) {
                Button("OK", role: .cancel) {}
            } message: {
                if case .failed(let reason) = model.markUnreadState { Text(reason) }
            }
    }

    private var failureShown: Binding<Bool> {
        Binding(
            get: { if case .failed = model.markUnreadState { true } else { false } },
            set: { if !$0 { model.clearMarkUnreadFailure() } }
        )
    }
}
