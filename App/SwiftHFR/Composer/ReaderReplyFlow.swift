import HFRModels
import SwiftUI

// Port of HFRswift/Swift/MessagesView.swift (MessagesView: reply action, composer sheet) and HFRswift/Swift/AnswerView.swift
// (AnswerView, "Répondre" title) @ 2440d79. Differences: HFR's own confirmation shown above the page.
/// The reader's reply entry (LOT-084): the "Répondre" button when the page offers an answer form and an account is
/// current, the composer sheet, and HFR's confirmation above the page once a reply is confirmed.
struct ReaderReplyFlow: ViewModifier {
    let model: TopicReaderModel
    /// The current account's composer; nil when logged out.
    let composer: ComposerServices?
    /// `reply_button_behavior`: `hidden` draws no button, `forum` the pencil, `quick` the plus (legacy `replyButtonSystemImage`).
    var behavior = ReplyButtonBehavior.quick
    @State private var reply: ReplyComposerModel?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top) {
                if model.error == nil, let confirmation = model.replyConfirmation {
                    ReplySentBanner(text: confirmation, close: model.clearReplyConfirmation)
                }
            }
            .task(id: model.replyConfirmation) {
                guard model.replyConfirmation != nil else { return }
                // Long enough to read; cancelled (and nothing hidden) when another confirmation replaces it.
                guard (try? await Task.sleep(for: .seconds(4))) != nil else { return }
                model.clearReplyConfirmation()
            }
            .toolbar {
                if composer != nil, model.replyTarget != nil, behavior != .hidden {
                    ToolbarItem(placement: .primaryAction) {
                        Button { Task { await model.requestReply() } } label: {
                            Label("Répondre", systemImage: behavior == .forum ? "square.and.pencil" : "plus")
                        }
                        .disabled(model.isLoadingQuote)
                    }
                }
            }
            // The reply button and every quote ask the reader; it hands over once, to the sheet that is not open yet.
            .onChange(of: model.pendingReply) { _, request in
                guard request != nil, let taken = model.takePendingReply() else { return }
                guard reply == nil else { return } // a sheet is open: the request was a double tap
                guard let composer, let target = model.replyTarget else {
                    // The answer form went away while the quote was fetched: say so instead of dropping the quote silently.
                    model.showMenuFeedback("Réponse indisponible : la page a changé, réessayez.")
                    return
                }
                reply = ReplyComposerModel(target: target, services: composer, quote: taken.quote)
            }
            .sheet(item: $reply) { composer in
                ReplyComposerView(model: composer) { reason in
                    Task { await model.composerDidClose(reason) }
                }
            }
    }
}

/// HFR's confirmation of a reply, above the page.
private struct ReplySentBanner: View {
    let text: String
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
            Text(text).scaledFont(.subheadline)
            Spacer()
            Button(action: close) { Image(systemName: "xmark") }
                .accessibilityLabel("Masquer")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}
