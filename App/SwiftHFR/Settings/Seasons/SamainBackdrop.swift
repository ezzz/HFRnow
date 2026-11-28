import SwiftUI

/// The Samain themes' art on the screen background (`SamainLayout`): static, so it stays with Reduce Motion; drawn once per size,
/// never touched, never read by VoiceOver (THEMES.md §4 rules 6–8). One layer, so where pieces overlap it is never denser than the
/// kind's opacity.
struct SamainBackdrop: View {
    let kind: SamainLayout.Kind
    @Environment(\.seasonalDecorationsHidden) private var hidden
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    /// The piece's image: the soft theme's bat as a silhouette in the draft's colour for the scheme, the rest as rendered.
    @ViewBuilder private func art(_ piece: SamainLayout.Piece) -> some View {
        if piece.art == .bat, kind == .soft {
            let colour = scheme == .dark ? SamainLayout.batOnDark : SamainLayout.batOnLight
            Image(piece.art.rawValue)
                .renderingMode(.template)
                .resizable()
                .foregroundStyle(Color(red: Double(colour.red) / 255, green: Double(colour.green) / 255, blue: Double(colour.blue) / 255))
        } else {
            Image(piece.art.rawValue).resizable()
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let size = CGSize(
                width: proxy.size.width + insets.leading + insets.trailing,
                height: proxy.size.height + insets.top + insets.bottom
            )
            ZStack(alignment: .topLeading) {
                ForEach(
                    Array(SamainLayout.pieces(kind, in: size, topInset: insets.top, bottomInset: insets.bottom).enumerated()),
                    id: \.offset
                ) { piece in
                    art(piece.element)
                        .frame(width: piece.element.frame.width, height: piece.element.frame.height)
                        .scaleEffect(x: piece.element.mirrored ? -1 : 1, y: 1)
                        .position(x: piece.element.frame.midX, y: piece.element.frame.midY)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .compositingGroup()
            .samainRim(scheme, enabled: kind == .soft)
            // The witch sweeps the decorations away: they fade as she passes, at once with Reduce Motion (THEMES.md §5).
            .opacity(hidden ? 0 : kind.opacity)
            .animation(reduceMotion ? nil : .easeIn(duration: NoelPackingModel.duration * 0.6), value: hidden)
            .offset(x: -insets.leading, y: -insets.top)
        }
        // The keyboard never moves the art.
        .ignoresSafeArea(.keyboard)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SeasonalDecorationsHiddenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The seasonal packing is playing: the decorations of the screens' backgrounds are on their way out.
    var seasonalDecorationsHidden: Bool {
        get { self[SeasonalDecorationsHiddenKey.self] }
        set { self[SeasonalDecorationsHiddenKey.self] = newValue }
    }
}
