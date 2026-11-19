import SwiftUI

/// The « Thème » choice as three image tiles, Clair, Sombre and Système (#1213): each a small mock screen drawn with SwiftUI shapes
/// from what the reader shows (`ThemeAppearance.tileLook`), Système split diagonally between the two, and a dot in the chosen
/// accent that follows the hue slider. A single-choice control for VoiceOver: each tile is a button, the chosen one carries the
/// selected trait, and the tiles wrap under large Dynamic Type sizes instead of clipping.
struct ThemeModeTiles: View {
    let appearance: ThemeAppearance
    @Binding var mode: ThemeSettingsModel.Mode
    // Dynamic Type scales the mock screen with its label.
    @ScaledMetric(relativeTo: .caption) private var tileHeight = 76.0
    @ScaledMetric(relativeTo: .caption) private var minimumWidth = 84.0
    @ScaledMetric(relativeTo: .caption) private var spacing = 12.0

    /// The tiles in the order the screen shows them (the enum's order is the stored one).
    private static let order: [ThemeSettingsModel.Mode] = [.light, .dark, .system]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: spacing, alignment: .top)], spacing: spacing) {
            ForEach(Self.order, id: \.self) { tile in
                let isSelected = tile == mode
                Button { mode = tile } label: {
                    VStack(spacing: 6) {
                        ThemeTileArt(mode: tile, appearance: appearance, isSelected: isSelected).frame(height: tileHeight)
                        Text(tile.tileTitle)
                            .font(.caption)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    }
                    .contentShape(Rectangle())
                }
                // A Form row with several controls: a plain button, or a tap anywhere in the row would press the first one.
                .buttonStyle(.plain)
                .accessibilityLabel(tile.tileAccessibilityLabel)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// The mock screen of one tile: a rounded card with two text lines and an accent dot; for Système the dark card is clipped to the
/// lower-right half of the light one.
private struct ThemeTileArt: View {
    let mode: ThemeSettingsModel.Mode
    let appearance: ThemeAppearance
    let isSelected: Bool
    @ScaledMetric(relativeTo: .caption) private var radius = 12.0
    @ScaledMetric(relativeTo: .caption) private var padding = 10.0

    var body: some View {
        ZStack {
            switch mode {
            case .light:
                card(appearance.tileLook(dark: false))
            case .dark:
                card(appearance.tileLook(dark: true))
            case .system:
                card(appearance.tileLook(dark: false))
                card(appearance.tileLook(dark: true)).clipShape(LowerRightHalf())
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .overlay {
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(
                    isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.4)), lineWidth: isSelected ? 3 : 1
                )
        }
        .accessibilityHidden(true) // the tile's button speaks for it
    }

    private func card(_ look: ThemeAppearance.TileLook) -> some View {
        ZStack(alignment: .topLeading) {
            Color(uiColor: look.surface.uiColor)
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(Color(uiColor: look.line.uiColor)).frame(height: 5)
                Capsule().fill(Color(uiColor: look.line.uiColor)).frame(width: 34, height: 5)
            }
            .padding(padding)
            Circle().fill(Color(uiColor: look.dot.uiColor)).frame(width: 12, height: 12)
                .padding(padding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }
}

/// The half of a rectangle below its anti-diagonal (from the top-right corner to the bottom-left one).
private struct LowerRightHalf: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
