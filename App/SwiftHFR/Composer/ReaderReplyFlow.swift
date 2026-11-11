import HFRModels
import SwiftUI

// Port of HFRswift/Swift/MessagesView.swift (MessagesView: reply action, composer sheet) and HFRswift/Swift/AnswerView.swift
// (AnswerView, "Répondre" title) @ 2440d79. Differences: HFR's own confirmation shown above the page.
/// The reader's reply entry (LOT-084): the composer sheet, and HFR's confirmation above the page once a reply is confirmed.
/// The "Répondre" button is in the reader's bottom bar (`ReaderPageControls`, LOT-186), as legacy's was.
struct ReaderReplyFlow: ViewModifier {
    let model: TopicReaderModel
    /// The current account's composer; nil when logged out.
    let composer: ComposerServices?
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
                ReaderAccessibility.announce(model.replyConfirmation)
                // Long enough to read; cancelled (and nothing hidden) when another confirmation replaces it.
                guard (try? await Task.sleep(for: .seconds(4))) != nil else { return }
                model.clearReplyConfirmation()
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
                ReplyComposerView(model: composer, pageScrolls: true) { reason in
                    Task { await model.composerDidClose(reason) }
                }
            }
            // The page under the sheet scrolls but ignores its taps while the sheet is up (#653).
            .onChange(of: reply != nil) { _, isOpen in model.composer(.reply, isOpen: isOpen) }
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
            Button(action: close) {
                Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44).contentShape(.rect) // 44 pt target
            }
            .accessibilityLabel("Masquer")
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12)) // floats over the page, which runs under it (LOT-186)
        .padding(.horizontal)
    }
}
