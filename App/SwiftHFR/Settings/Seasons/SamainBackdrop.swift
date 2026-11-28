import SwiftUI

/// The Samain themes' art on the screen background (`SamainLayout`): static, so it stays with Reduce Motion; drawn once per size,
/// never touched, never read by VoiceOver (THEMES.md §4 rules 6–8). One layer, so where pieces overlap it is never denser than the
/// kind's opacity.
struct SamainBackdrop: View {
    let kind: SamainLayout.Kind

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
                    Image(piece.element.art.rawValue)
                        .resizable()
                        .frame(width: piece.element.frame.width, height: piece.element.frame.height)
                        .scaleEffect(x: piece.element.mirrored ? -1 : 1, y: 1)
                        .position(x: piece.element.frame.midX, y: piece.element.frame.midY)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .compositingGroup()
            .opacity(kind.opacity)
            .offset(x: -insets.leading, y: -insets.top)
        }
        // The keyboard never moves the art.
        .ignoresSafeArea(.keyboard)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
