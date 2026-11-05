import SwiftUI

/// The BBCode buttons under the editor: tags, then the colour palette. Thin: every rule is in `ComposerFormattingModel`.
struct FormattingToolbar: View {
    let model: ComposerFormattingModel
    /// Called after a tap so the editor keeps focus (the keyboard stays up).
    let refocus: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                if model.isPaletteShown { palette } else { tags }
            }
            .padding(.horizontal, 8)
        }
        .background(.bar)
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
                    .frame(width: 24, height: 24)
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
            content().frame(minWidth: 44, minHeight: 44).contentShape(.rect)
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
