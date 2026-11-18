import SwiftUI

/// EXPERIMENTAL(denseRows, #1107): the dense look of every list (`ListLook.dense`), the edge-to-edge look the category topic lists
/// had as a plain list (before #1081): no card, the rows on the screen's background from one side to the other, a highlighted row
/// a pill 4 pt from the edge (`RowTint.edgeGap`). The rows keep the density's insets (`ListDensity.rowInsets`).
enum DenseListLook {
    /// Outer side margin of the list: none, the rows reach the safe-area edge.
    static let outerMargin: CGFloat = 0

    /// The rows' background: none, so no card shows; a row's pill (`rowPill`) still draws its highlight.
    static let rowBackground = Color.clear

    /// Catégories (#1107): the vertical inset of a category row, tighter than the system's (about 11 pt).
    static let categoryRowVerticalInset: CGFloat = 5

    /// Catégories (#1107): the space between a category's icon and its title, wider than the classic 12 pt so the row breathes
    /// sideways while it loses height.
    static let categoryIconSpacing: CGFloat = 16

    /// Catégories (#1107): the space between a category's title and its sub-forum count (classic 4 pt).
    static let categoryLineSpacing: CGFloat = 1
}

extension View {
    /// EXPERIMENTAL(denseRows, #1107): a category row's vertical insets in the dense look; the classic look keeps the system's.
    func denseCategoryRowInsets(_ look: ListLook) -> some View {
        listRowInsets(.vertical, look == .dense ? DenseListLook.categoryRowVerticalInset : nil)
    }
}
