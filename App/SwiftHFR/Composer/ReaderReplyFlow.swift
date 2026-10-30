import SwiftUI

/// The reader's reply entry (LOT-084): the "Répondre" button when the page offers an answer form and an account is
/// current, the composer sheet, and HFR's confirmation above the page once a reply is confirmed.
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
                // Long enough to read; cancelled (and nothing hidden) when another confirmation replaces it.
                guard (try? await Task.sleep(for: .seconds(4))) != nil else { return }
                model.clearReplyConfirmation()
            }
            .toolbar {
                if let composer, let target = model.replyTarget {
                    ToolbarItem(placement: .primaryAction) {
                        Button { reply = ReplyComposerModel(target: target, services: composer) } label: {
                            Label("Répondre", systemImage: "square.and.pencil")
                        }
                    }
                }
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
            Text(text).font(.subheadline)
            Spacer()
            Button(action: close) { Image(systemName: "xmark") }
                .accessibilityLabel("Masquer")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}
