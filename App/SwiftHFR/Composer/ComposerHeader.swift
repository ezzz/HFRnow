import SwiftUI

/// Where the composer's controls sit (#854, operator 2026-11-12, reference: the Claude app's composer): on an iPhone the control
/// row inside the text card's bottom edge, and close, drafts and send as small floating glass buttons; an iPad keeps legacy's
/// bar and the row under the card.
enum ComposerChrome: Equatable {
    /// An iPhone: the lighter composer docked on the keyboard.
    case docked
    /// An iPad: legacy's top bar and control row.
    case sheet

    init(isPhone: Bool) { self = isPhone ? .docked : .sheet }

    /// The control row sits inside the text card, on its bottom edge.
    var controlsInCard: Bool { self == .docked }
    /// Close, drafts and send are small floating buttons instead of legacy's bar.
    var headerFloats: Bool { self == .docked }
}

// Port of HFRswift/Swift/AnswerView.swift (composerHeader `:768-819`, composerCloseButtonStyle, composerDraftButtonStyle,
// composerSendButtonStyle `:1704-1745`) @ 87fe0d1c. Differences: drawn on the docked card instead of a full-screen cover (#653,
// GAP-653); on an iPhone the buttons are small floating glass capsules and the title a light caption (#854, GAP-653); the drafts
// button only where LOT-101 archives drafts (a topic's reply); the title follows Dynamic Type.
/// The composer's top bar, as legacy's (#653, operator reference of 2026-11-10): close `xmark` and the drafts `tray` on the left,
/// the title in the middle, send `arrow.up` on the right, greyed while there is nothing to send and a spinner while sending.
/// On an iPhone (`floats`) the same buttons, smaller and lighter, float above the text card (#854).
struct ComposerHeader: View {
    let title: String
    let isSending: Bool
    let canSend: Bool
    /// LOT-101's drafts of this topic: nil hides the button (legacy shows it only with a draft context).
    let drafts: Drafts?
    /// Small floating buttons (an iPhone, `ComposerChrome.headerFloats`) instead of legacy's bar.
    var floats = false
    let close: () -> Void
    let send: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var floatingGlyph: CGFloat = 16

    /// The drafts button's state and action.
    struct Drafts {
        /// Some drafts are archived: the button is prominent, as legacy's.
        let hasDrafts: Bool
        let isEnabled: Bool
        let open: () -> Void
    }

    /// The send button's look: greyed with nothing to send, prominent with something, a spinner while sending.
    struct SendState: Equatable {
        let isEnabled: Bool
        let isProminent: Bool
        let showsSpinner: Bool
        /// VoiceOver's label.
        let label: String

        init(isSending: Bool, canSend: Bool) {
            isEnabled = canSend
            isProminent = canSend
            showsSpinner = isSending
            label = isSending ? "Envoi en cours" : "Envoyer"
        }
    }

    /// Close waits for a send to end.
    static func closeIsEnabled(isSending: Bool) -> Bool { !isSending }

    /// The drafts open once the draft is read, never during a send.
    static func draftsAreEnabled(_ drafts: Drafts, isSending: Bool) -> Bool { drafts.isEnabled && !isSending }

    var body: some View {
        ZStack {
            Text(title)
                .font(floats ? .subheadline.weight(.semibold) : .headline)
                .foregroundStyle(floats ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, floats ? 84 : 96)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: floats ? 6 : 8) {
                closeButton
                if let drafts {
                    draftsButton(drafts)
                }
                Spacer()
                sendButton
            }
        }
        .frame(minHeight: floats ? 32 : 44)
    }

    private var closeButton: some View {
        Button(action: close) { symbol("xmark", size: 14) }
            .modifier(ButtonShape(floats: floats))
            .buttonStyle(.glass)
            .disabled(!Self.closeIsEnabled(isSending: isSending))
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Fermer")
    }

    private func draftsButton(_ drafts: Drafts) -> some View {
        Button(action: drafts.open) { symbol("tray", size: 15, weight: .semibold) }
            .modifier(ButtonShape(floats: floats))
            .modifier(GlassStyle(isProminent: drafts.hasDrafts))
            .disabled(!Self.draftsAreEnabled(drafts, isSending: isSending))
            .accessibilityLabel("Brouillons")
    }

    private var sendButton: some View {
        let state = SendState(isSending: isSending, canSend: canSend)
        return Button(action: send) {
            if state.showsSpinner {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: glyphFrame, height: glyphFrame)
                    .padding(glyphPadding)
                    .accessibilityLabel(state.label)
            } else {
                symbol("arrow.up", size: 16)
            }
        }
        .modifier(ButtonShape(floats: floats))
        .modifier(GlassStyle(isProminent: state.isProminent))
        .disabled(!state.isEnabled)
        .accessibilityLabel(state.label)
    }

    /// The symbol's box: legacy's 18 pt, or the floating buttons' size, which follows Dynamic Type.
    private var glyphFrame: CGFloat { floats ? floatingGlyph : 18 }
    private var glyphPadding: CGFloat { floats ? 2 : 8 }

    private func symbol(_ name: String, size: CGFloat, weight: Font.Weight = .bold) -> some View {
        Image(systemName: name)
            .font(floats ? .subheadline.weight(weight) : .system(size: size, weight: weight))
            .frame(width: glyphFrame, height: glyphFrame)
            .padding(glyphPadding)
    }
}

/// Legacy's round buttons, or the small floating capsules of an iPhone (#854).
private struct ButtonShape: ViewModifier {
    let floats: Bool

    func body(content: Content) -> some View {
        if floats {
            content.buttonBorderShape(.capsule).controlSize(.small)
        } else {
            content.buttonBorderShape(.circle)
        }
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
