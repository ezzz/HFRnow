import SwiftUI

/// A theme's screen background (LOT-188), with its art behind the content when it has any (LOT-166: Noël abusé's `noel-full`).
struct ThemeScreenBackdrop: View {
    let fill: Color
    let decorations: String?

    var body: some View {
        ZStack {
            fill
            if decorations == SeasonalTheme.noelAbuseDecorations {
                NoelAbuseBackdrop()
            }
        }
    }
}

extension SeasonalTheme {
    /// The decorations id of Noël abusé's theme file.
    static let noelAbuseDecorations = "noel-full"
}

/// Noël abusé's art on the background (`NoelAbuseLayout`): static, so it stays with Reduce Motion; drawn once per size, never
/// touched, never read by VoiceOver (THEMES.md §4 rules 6–8).
private struct NoelAbuseBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            let size = CGSize(
                width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            )
            let top = proxy.safeAreaInsets.top
            let bottom = proxy.safeAreaInsets.bottom
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    guard let star = context.resolveSymbol(id: 0) else { return }
                    for point in NoelAbuseLayout.stars(in: size) { context.draw(star, at: point) }
                } symbols: {
                    Image("NoelStar").resizable().frame(width: NoelAbuseLayout.starSide, height: NoelAbuseLayout.starSide).tag(0)
                }
                ForEach(NoelAbuseLayout.garland(in: size, topInset: top).enumerated(), id: \.offset) { piece in
                    ArtImage(name: "NoelGarland", frame: piece.element)
                }
                ForEach(NoelAbuseLayout.ornaments(in: size, topInset: top).enumerated(), id: \.offset) { ornament in
                    ArtImage(name: "NoelOrnament", frame: ornament.element)
                }
                if let tree = NoelAbuseLayout.tree(in: size, bottomInset: bottom) {
                    ArtImage(name: "NoelTree", frame: tree)
                }
                ForEach(NoelAbuseLayout.gifts(in: size, bottomInset: bottom).enumerated(), id: \.offset) { gift in
                    ArtImage(name: ["NoelGift", "NoelGiftBlue", "NoelGiftGold"][gift.offset % 3], frame: gift.element)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            // One layer, then faded: where pieces overlap (a star behind the tree) the art is never denser than `artOpacity`.
            .compositingGroup()
            .opacity(NoelAbuseLayout.artOpacity)
            .offset(x: -proxy.safeAreaInsets.leading, y: -top)
        }
        // The keyboard never moves the art: the tree and gifts stay on the home indicator's inset behind the composer.
        .ignoresSafeArea(.keyboard)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One piece of art at its frame, in the backdrop's coordinates.
private struct ArtImage: View {
    let name: String
    let frame: CGRect

    var body: some View {
        Image(name)
            .resizable()
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }
}
