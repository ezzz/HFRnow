import HFRStorage
import SwiftUI

// Port of HFRswift/Swift/AnswerView.swift (composerHeader `:768-819`) @ 87fe0d1c. Differences: no title strip (#972, operator
// 2026-11-16): close `xmark` and drafts `tray` on the left, send `arrow.up` on the right, directly above the card, as circles
// of the card tools' diameter (`ComposerToolSize`, #1126) in 44 pt hit areas (#854) on an opaque-enough fill so they read over
// any page (#972), `FloatingSpacing.gap` from the sides and the card (#895); GAP-653.
/// The modern composer's floating buttons (#904, Réglages › Expérimental › « Composer moderne »): close and drafts on the left,
/// send on the right, nothing between them. The title legacy's bar shows is the row's VoiceOver label only.
struct FloatingComposerButtons: View {
    /// What legacy's bar shows as its title (« Répondre », « Edition »…): announced, not drawn.
    let title: String
    let isSending: Bool
    let canSend: Bool
    let drafts: ComposerHeader.Drafts?
    /// The card tools' size (#895, #1126): the circle's diameter, the glyph's point size and weight.
    let size: ComposerToolSize
    let close: () -> Void
    let send: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            button(
                prominent: false, enabled: ComposerHeader.closeIsEnabled(isSending: isSending), circle: .closeCircle,
                action: close
            ) {
                symbol("xmark", probe: .closeGlyph)
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Fermer")
            .composerProbe(.close)
            if let drafts {
                button(
                    prominent: drafts.hasDrafts, enabled: ComposerHeader.draftsAreEnabled(drafts, isSending: isSending),
                    circle: .draftsCircle, action: drafts.open
                ) {
                    symbol("tray")
                }
                .accessibilityLabel("Brouillons")
                .composerProbe(.drafts)
            }
            Spacer(minLength: 0)
            sendButton
                .composerProbe(.send)
        }
        .frame(minHeight: ComposerHeader.hitSize)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        // The capsules sit `FloatingSpacing.gap` from the sides, the page and the card: their hit areas' slack counts (#895).
        .padding(ComposerChrome.docked.headerInsets(diameter: size.diameter))
        // Where the docked bar's fill starts (#972, `DockedComposerBar`).
        .background {
            GeometryReader { Color.clear.preference(key: ComposerButtonsHeightKey.self, value: $0.size.height) }
        }
    }

    private var sendButton: some View {
        let state = ComposerHeader.SendState(isSending: isSending, canSend: canSend)
        return button(prominent: state.isProminent, enabled: state.isEnabled, circle: .sendCircle, action: send) {
            if state.showsSpinner {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: size.glyph, height: size.glyph)
                    .accessibilityLabel(state.label)
            } else {
                symbol("arrow.up")
            }
        }
        .accessibilityLabel(state.label)
    }

    /// A circle of the card tools' diameter inside a 44 pt hit area: the palette's fill under the system's interactive glass, so
    /// the glyph keeps its contrast whatever page runs under it (#972); a prominent one is the accent, as before. `.plain` draws
    /// no disabled state: only the glyph dims, the circle stays readable as a button.
    private func button<Label: View>(
        prominent: Bool, enabled: Bool, circle: ComposerLayoutProbe.Part? = nil, action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        let palette = FloatingButtonPalette(scheme: scheme)
        return Button(action: action) {
            label()
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(palette.glyph.color))
                .opacity(enabled ? 1 : FloatingButtonPalette.disabledGlyphOpacity)
                .frame(width: size.diameter, height: size.diameter)
                .background { probed(circle) }
                .background {
                    if !prominent {
                        Circle()
                            .fill(palette.fill.color)
                            .overlay {
                                Circle().strokeBorder(palette.glyph.color.opacity(FloatingButtonPalette.strokeOpacity), lineWidth: 0.5)
                            }
                    }
                }
                .glassEffect(prominent ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .circle)
                .frame(minWidth: ComposerHeader.hitSize, minHeight: ComposerHeader.hitSize)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// An invisible shape of the circle's size that reports its frame to a test's probe (`part`), if any.
    @ViewBuilder
    private func probed(_ part: ComposerLayoutProbe.Part?) -> some View {
        if let part { Color.clear.composerProbe(part) }
    }

    /// The glyph at the card tools' size and weight (`ComposerControlRow`), so the composer has one icon size (#895, #1126).
    private func symbol(_ name: String, probe part: ComposerLayoutProbe.Part? = nil) -> some View {
        let image = Image(systemName: name).font(.system(size: size.glyph, weight: ComposerToolSize.glyphWeight))
        return Group {
            if let part { image.composerProbe(part) } else { image }
        }
        .frame(width: size.glyph, height: size.glyph)
    }
}

/// The floating buttons' colours (#972, operator 2026-11-16: "slightly more visible", they faded into the page): a near-opaque
/// capsule in the scheme's background colour and a strong glyph. The capsule's opacity bounds what the page can do to it, so
/// the glyph's contrast is checked against the capsule laid over a white page and over a black one (`composited(over:)`).
struct FloatingButtonPalette: Equatable {
    /// The glyph's colour.
    let glyph: ThemeColor
    /// The capsule's fill, its alpha the share of the page it hides.
    let fill: ThemeColor

    /// A disabled glyph (send with nothing to send, close during a send): dimmed, the capsule kept.
    static let disabledGlyphOpacity: Double = 0.4
    /// The hairline around the capsule, in the glyph's colour, so a capsule over a page of its own colour keeps an edge.
    static let strokeOpacity: Double = 0.15

    init(scheme: ColorScheme) {
        switch scheme {
        case .dark:
            glyph = ThemeAppearance.darkText
            fill = ThemeColor(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255, alpha: 0.85)
        default:
            glyph = ThemeColor(hex: 0x1C1C1E)
            fill = ThemeColor(red: 1, green: 1, blue: 1, alpha: 0.85)
        }
    }
}

extension ThemeColor {
    /// This colour, with its alpha, laid over an opaque `page`.
    func composited(over page: ThemeColor) -> ThemeColor {
        func mix(_ top: Double, _ bottom: Double) -> Double { top * alpha + bottom * (1 - alpha) }
        return ThemeColor(red: mix(red, page.red), green: mix(green, page.green), blue: mix(blue, page.blue))
    }

    /// The SwiftUI colour (sRGB).
    var color: Color { Color(uiColor: uiColor) }
}
