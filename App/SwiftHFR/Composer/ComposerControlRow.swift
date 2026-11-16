import SwiftUI

// Port of HFRswift/Swift/AnswerView.swift (composerToolbar, editionGroup, insertionGroup, ComposerToolbarGroup, ComposerToolbarButton,
// `:940-1054`, `:1656-1705`) @ 87fe0d1c. Differences: cells sized by density, Dynamic Type and the text scale (#598,
// `ComposerBarMetrics`); the GIF button only when Giphy is configured (LOT-155); the upload symbol is `photo.badge.plus`, the
// bar's `[img]` keeping `photo` (LOT-174); GAP-086, GAP-085 (the bar behind "Aa"); on an iPhone the row sits inside the text
// card, its buttons on the card's glass instead of two glass capsules (#854, GAP-653).
/// The composer's control row (#653), above the keyboard: "Vider le texte", "Annuler", "Rétablir" on the left; Smileys, GIF,
/// image and "Aa" (the formatting bar, shown above the row) on the right. Two lines when one does not fit (Dynamic Type XL),
/// as legacy's `ViewThatFits`. On an iPhone (`inCard`) it is the text card's bottom edge (#854). Thin: the rules are in
/// `ReplyComposerModel` and `ComposerFormattingModel`.
struct ComposerControlRow: View {
    let model: ReplyComposerModel
    let formatting: ComposerFormattingModel
    /// Giphy is configured: the GIF button shows.
    let offersGif: Bool
    let openSmileys: () -> Void
    let openGif: () -> Void
    let openImages: () -> Void
    /// Called after an edit of the text so the editor keeps focus (the keyboard stays up).
    let refocus: () -> Void
    /// Inside the text card (an iPhone, `ComposerChrome.controlsInCard`): the buttons sit on the card's glass, no capsules of
    /// their own (glass is not stacked on glass).
    var inCard = false
    @Environment(\.listDensity) private var density
    @Environment(\.textScale) private var scale
    @ScaledMetric(relativeTo: .body) private var dynamicType: CGFloat = 1

    private var metrics: ComposerBarMetrics { ComposerBarMetrics(density: density, scale: scale, dynamicType: dynamicType) }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    edition
                    Spacer(minLength: 0)
                    insertion
                }
                VStack(alignment: .leading, spacing: 8) {
                    edition
                    insertion
                }
            }
        }
        .padding(.horizontal, inCard ? 4 : 12)
        .padding(.vertical, inCard ? 2 : 6)
    }

    private var edition: some View {
        group {
            button("Vider le texte", symbol: "xmark.circle", enabled: model.canClear, tint: .red) {
                formatting.clear()
                refocus()
            }
            button("Annuler", symbol: "arrow.uturn.backward", enabled: model.canUndo) {
                formatting.undo()
                refocus()
            }
            button("Rétablir", symbol: "arrow.uturn.forward", enabled: model.canRedo) {
                formatting.redo()
                refocus()
            }
        }
    }

    private var insertion: some View {
        group {
            button("Smileys", symbol: "face.smiling", enabled: model.canEdit, action: openSmileys)
            if offersGif {
                button("GIF Giphy", symbol: "g.circle", enabled: model.canEdit, action: openGif)
            }
            button("Insérer image", symbol: "photo.badge.plus", enabled: model.canEdit, action: openImages)
            button(
                formatting.isBarShown ? "Masquer les styles" : "Afficher les styles", symbol: "textformat",
                enabled: model.canEdit, tint: formatting.isBarShown ? Color.accentColor : nil
            ) {
                formatting.toggleBar()
            }
            .accessibilityAddTraits(formatting.isBarShown ? .isSelected : [])
        }
    }

    /// One capsule of buttons (legacy `ComposerToolbarGroup`); in the card, the buttons alone.
    @ViewBuilder
    private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if inCard {
            HStack(spacing: 0) { content() }
        } else {
            HStack(spacing: 0) { content() }
                .padding(.horizontal, 4)
                .glassEffect(.regular, in: .capsule)
        }
    }

    private func button(
        _ label: String, symbol: String, enabled: Bool, tint: Color? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: metrics.glyphSize, weight: .medium))
                .foregroundStyle(tint ?? .primary)
                .frame(minWidth: metrics.cellSize, minHeight: metrics.cellSize)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // `.plain` draws no disabled state: dimmed as legacy's `opacity(isDisabled ? 0.4 : 1)`.
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }
}
