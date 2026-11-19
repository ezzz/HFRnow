import SwiftUI

// Port of HFRswift/Swift/AnswerView.swift (composerHeader `:768-819`, composerCloseButtonStyle, composerDraftButtonStyle,
// composerSendButtonStyle `:1704-1745`) @ 87fe0d1c. Differences: drawn on the docked card instead of a full-screen cover (#653,
// GAP-653); with the modern composer the buttons float with no title (`FloatingComposerButtons`, #854, #895, #972); the drafts
// button only where LOT-101 archives drafts (a topic's reply); the title follows Dynamic Type; the buttons take the card tools' diameter,
// glyph size and weight (`ComposerToolSize`, #1126).
/// The composer's top bar, as legacy's (#653, operator reference of 2026-11-10): close `xmark` and the drafts `tray` on the left,
/// the title in the middle, send `arrow.up` on the right, greyed while there is nothing to send and a spinner while sending.
/// On an iPhone with the modern composer (`floats`) the same buttons, smaller, float above the text card with no title (#972).
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
    @Environment(\.listDensity) private var density
    @Environment(\.textScale) private var scale
    @ScaledMetric(relativeTo: .body) private var dynamicType: CGFloat = 1

    /// The most the text size (Dynamic Type times the app's text scale) grows these three buttons: past it they keep that size and
    /// offer the Large Content Viewer, as the system's bars do. At 1.8 the cell is 86 pt at most, so three of them and the bar's
    /// insets fit the narrowest supported width (320 pt) in both rows (#1126).
    static let maxScaleFactor: CGFloat = 1.8

    /// The size of the bar's close, drafts and send buttons: the card tools' (#1126), one source for both rows, up to
    /// `maxScaleFactor`. `inCard` is the chrome's `controlsInCard`: the bar then agrees with the row it sits over.
    static func buttonSize(metrics: ComposerBarMetrics, inCard: Bool) -> ComposerToolSize {
        ComposerToolSize(metrics: metrics.capped(at: maxScaleFactor), inCard: inCard)
    }

    /// What the bar's sides and the gaps between its buttons take: the floating row has the gap on each side, legacy's bar its
    /// 16 pt insets and 8 pt spacing.
    static func reservedWidth(floats: Bool, buttons: Int) -> CGFloat {
        floats ? 2 * FloatingSpacing.gap : 32 + 8 * CGFloat(max(0, buttons - 1))
    }

    private var toolSize: ComposerToolSize {
        Self.buttonSize(
            metrics: ComposerBarMetrics(density: density, scale: scale, dynamicType: dynamicType), inCard: chrome.controlsInCard
        )
    }

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

    /// The hit area of each floating button: the capsule is drawn small, as the Claude app's (operator, 2026-11-13), the tap
    /// target keeps the 44 pt of the HIG.
    static let hitSize: CGFloat = 44

    /// A floating button's size: a circle of the card tools' diameter (#1126).
    static func capsuleSize(diameter: CGFloat) -> CGSize { CGSize(width: diameter, height: diameter) }

    /// The space between a capsule and the edge of its 44 pt hit area, on each side (none once the capsule outgrows it).
    static func hitSlack(diameter: CGFloat) -> CGSize {
        let capsule = capsuleSize(diameter: diameter)
        return CGSize(width: max(0, (hitSize - capsule.width) / 2), height: max(0, (hitSize - capsule.height) / 2))
    }

    var body: some View {
        // EXPERIMENTAL(modernComposer, #904): replaces legacy's bar by the floating buttons, with no title strip (#972).
        if floats {
            FloatingComposerButtons(
                title: title, isSending: isSending, canSend: canSend, drafts: drafts, size: toolSize, close: close, send: send
            )
        } else {
            legacyBar
        }
    }

    /// The chrome this bar is drawn for.
    private var chrome: ComposerChrome { floats ? .docked : .sheet }

    /// An iPad: legacy's bar, the title centred over the row.
    private var legacyBar: some View {
        HStack(spacing: 8) {
            closeButton
            if let drafts {
                draftsButton(drafts)
            }
            Spacer()
            sendButton
        }
        // An overlay, so the title never widens the bar: it takes what the buttons leave (and none when they take it all).
        .overlay {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                // Room for the close and drafts buttons on each side, whatever the metrics make them (#1126).
                .padding(.horizontal, 2 * toolSize.diameter + 28)
                .accessibilityAddTraits(.isHeader)
                // Drawn over the buttons' row (an overlay, so it never widens the bar): it takes no tap, so the edge of the drafts
                // button under it at large text sizes keeps its own (#1137, review of #1129). No test covers it: a hit test on the
                // overlay needs a device (#893).
                .allowsHitTesting(false)
                .composerProbe(.title)
        }
        .frame(minHeight: 44)
        .padding(chrome.headerInsets(diameter: toolSize.diameter))
    }

    private var closeButton: some View {
        Button(action: close) { symbol("xmark", circle: .closeCircle) }
            .buttonBorderShape(.circle)
            .buttonStyle(.glass)
            .disabled(!Self.closeIsEnabled(isSending: isSending))
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Fermer")
            .accessibilityShowsLargeContentViewer()
    }

    private func draftsButton(_ drafts: Drafts) -> some View {
        Button(action: drafts.open) { symbol("tray", circle: .draftsCircle) }
            .buttonBorderShape(.circle)
            .modifier(GlassStyle(isProminent: drafts.hasDrafts))
            .disabled(!Self.draftsAreEnabled(drafts, isSending: isSending))
            .accessibilityLabel("Brouillons")
            .accessibilityShowsLargeContentViewer()
    }

    private var sendButton: some View {
        let state = SendState(isSending: isSending, canSend: canSend)
        return Button(action: send) {
            if state.showsSpinner {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: toolSize.diameter, height: toolSize.diameter)
                    .accessibilityLabel(state.label)
            } else {
                symbol("arrow.up", circle: .sendCircle)
            }
        }
        .buttonBorderShape(.circle)
        .modifier(GlassStyle(isProminent: state.isProminent))
        .disabled(!state.isEnabled)
        .accessibilityLabel(state.label)
        .accessibilityShowsLargeContentViewer()
    }

    /// A glyph in the card tools' circle: their diameter, glyph size and weight (#1126); the glass behind it is the bar's own.
    private func symbol(_ name: String, circle: ComposerLayoutProbe.Part) -> some View {
        Image(systemName: name)
            .font(.system(size: toolSize.glyph, weight: ComposerToolSize.glyphWeight))
            .frame(width: toolSize.diameter, height: toolSize.diameter)
            .composerProbe(circle)
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
