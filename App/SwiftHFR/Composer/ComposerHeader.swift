import SwiftUI

// Port of HFRswift/Swift/AnswerView.swift (composerHeader `:768-819`, composerCloseButtonStyle, composerDraftButtonStyle,
// composerSendButtonStyle `:1704-1745`) @ 87fe0d1c. Differences: drawn on the docked card instead of a full-screen cover (#653,
// GAP-653); the drafts button only where LOT-101 archives drafts (a topic's reply); the title follows Dynamic Type.
/// The composer's top bar, as legacy's (#653, operator reference of 2026-11-10): close `xmark` and the drafts `tray` on the left,
/// the title in the middle, send `arrow.up` on the right, greyed while there is nothing to send and a spinner while sending.
struct ComposerHeader: View {
    let title: String
    let isSending: Bool
    let canSend: Bool
    /// LOT-101's drafts of this topic: nil hides the button (legacy shows it only with a draft context).
    let drafts: Drafts?
    let close: () -> Void
    let send: () -> Void

    /// The drafts button's state and action.
    struct Drafts {
        /// Some drafts are archived: the button is prominent, as legacy's.
        let hasDrafts: Bool
        let isEnabled: Bool
        let open: () -> Void
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 96)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: close) { symbol("xmark", size: 14) }
                    .buttonBorderShape(.circle)
                    .buttonStyle(.glass)
                    .disabled(isSending)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Fermer")
                if let drafts {
                    draftsButton(drafts)
                }
                Spacer()
                sendButton
            }
        }
        .frame(minHeight: 44)
    }

    private func draftsButton(_ drafts: Drafts) -> some View {
        Button(action: drafts.open) { symbol("tray", size: 15, weight: .semibold) }
            .buttonBorderShape(.circle)
            .modifier(GlassStyle(isProminent: drafts.hasDrafts))
            .disabled(!drafts.isEnabled || isSending)
            .accessibilityLabel("Brouillons")
    }

    private var sendButton: some View {
        Button(action: send) {
            if isSending {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18, height: 18)
                    .padding(8)
                    .accessibilityLabel("Envoi en cours")
            } else {
                symbol("arrow.up", size: 16)
            }
        }
        .buttonBorderShape(.circle)
        .modifier(GlassStyle(isProminent: canSend))
        .disabled(!canSend)
        .accessibilityLabel(isSending ? "Envoi en cours" : "Envoyer")
    }

    private func symbol(_ name: String, size: CGFloat, weight: Font.Weight = .bold) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: weight))
            .frame(width: 18, height: 18)
            .padding(8)
    }
}

/// Legacy's glass button, prominent (tinted) when it leads somewhere: the send button with something to send, the drafts
/// button with drafts.
private struct GlassStyle: ViewModifier {
    let isProminent: Bool

    func body(content: Content) -> some View {
        if isProminent { content.buttonStyle(.glassProminent) } else { content.buttonStyle(.glass) }
    }
}
