import SwiftUI

/// Size of the bar's cells (#598): 48 pt in regular density, 40 pt in compact, times Dynamic Type and the app's text scale
/// (LOT-169: the percentage multiplies the system size, so accessibility sizes still grow the bar).
struct ComposerBarMetrics: Equatable {
    let density: ListDensity
    let scale: TextScale
    /// The Dynamic Type factor (`@ScaledMetric` of 1 relative to the body style).
    var dynamicType: CGFloat = 1

    /// Height and minimum width of one cell.
    var cellSize: CGFloat { (density == .compact ? 40 : 48) * dynamicType * scale.factor }
    /// Diameter of a colour swatch: half the cell, as the legacy 24 pt in a 48 pt cell.
    var swatchSize: CGFloat { cellSize / 2 }
    /// Point size of a button's symbol.
    var glyphSize: CGFloat { cellSize * 0.4 }
}

/// The BBCode buttons under the editor: tags, then the colour palette. Thin: every rule is in `ComposerFormattingModel`.
struct FormattingToolbar: View {
    let model: ComposerFormattingModel
    /// Called after a tap so the editor keeps focus (the keyboard stays up).
    let refocus: () -> Void
    @Environment(\.listDensity) private var density
    @Environment(\.textScale) private var scale
    @ScaledMetric(relativeTo: .body) private var dynamicType: CGFloat = 1

    private var metrics: ComposerBarMetrics { ComposerBarMetrics(density: density, scale: scale, dynamicType: dynamicType) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                if model.isPaletteShown { palette } else { tags }
            }
            .padding(.horizontal, 8)
        }
        .background(.bar)
        // One container for VoiceOver ("Mise en forme"), its buttons inside (LOT-163).
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mise en forme")
    }

    @ViewBuilder
    private var tags: some View {
        ForEach(BBCodeTag.allCases, id: \.rawValue) { tag in
            button(tag.label) { model.tap(.bbCode(tag)) } content: { Image(systemName: tag.systemImage) }
        }
        button("Choisir une couleur") { model.isPaletteShown = true } content: { Image(systemName: "paintpalette") }
    }

    @ViewBuilder
    private var palette: some View {
        button("Retour aux styles") { model.isPaletteShown = false } content: { Image(systemName: "chevron.left") }
        ForEach(ReplyTextColor.palette) { color in
            button("Couleur \(color.name)") { model.tap(.color(color)) } content: {
                Circle()
                    .fill(Self.swiftUIColor(hex: color.hex))
                    .overlay { Circle().stroke(Color.primary.opacity(0.4), lineWidth: 1) }
                    .frame(width: metrics.swatchSize, height: metrics.swatchSize)
            }
        }
    }

    private func button<Content: View>(
        _ label: String, action: @escaping () -> Void, @ViewBuilder content: () -> Content
    ) -> some View {
        Button {
            action()
            refocus()
        } label: {
            content()
                .font(.system(size: metrics.glyphSize))
                .frame(minWidth: metrics.cellSize, minHeight: metrics.cellSize).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!model.isEnabled)
        .opacity(model.isEnabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }

    private static func swiftUIColor(hex: String) -> Color {
        let value = Int(hex, radix: 16) ?? 0
        return Color(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255)
    }
}
