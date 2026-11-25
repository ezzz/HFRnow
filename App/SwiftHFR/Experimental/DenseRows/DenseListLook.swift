import SwiftUI

/// EXPERIMENTAL(denseRows, #1107): the dense look of every list (`ListLook.dense`), the edge-to-edge look of a plain list: no card,
/// the rows on the plain list's background (or the theme's) from one side to the other, a highlighted row a pill 4 pt from the
/// edge (`RowTint.edgeGap`). The rows keep the density's insets (`ListDensity.rowInsets`).
enum DenseListLook {
    /// Outer side margin of the list: none, the rows reach the safe-area edge.
    static let outerMargin: CGFloat = 0

    /// The rows' background: none, so no card shows; a row's pill (`rowPill`) still draws its highlight.
    static let rowBackground = Color.clear

    /// The list's background where no theme paints the screen: the plain list's (white in light, black in dark), not the
    /// grouped grey (operator's screenshot, decided by mac/M1 on #1117).
    static let plainBackground = Color(uiColor: .systemBackground)

    /// A selected row's background: the clear row would hide the list's own selection (iPad columns), as `BookmarksView` does.
    static let selectedRowBackground = ListLook.selectedRowBackground

    /// Catégories (#1107): the vertical inset of a category row, tighter than the system's (about 11 pt).
    static let categoryRowVerticalInset: CGFloat = 5

    /// Catégories (#1107): the space between a category's icon and its title, wider than the classic 12 pt so the row breathes
    /// sideways while it loses height.
    static let categoryIconSpacing: CGFloat = 16

    /// Catégories (#1107): the space between a category's title and its sub-forum count (classic 4 pt).
    static let categoryLineSpacing: CGFloat = 1
}

/// EXPERIMENTAL(denseRows, #1107): the large-title row in the dense look: no band behind it, the title on the list's background.
/// The classic look keeps today's row as it is: nil leaves the system's card behind the title.
private struct DenseTitleRow: ViewModifier {
    @Environment(\.listLook) private var look

    func body(content: Content) -> some View {
        content.listRowBackground(look == .dense ? DenseListLook.rowBackground : nil)
    }
}

extension View {
    /// EXPERIMENTAL(denseRows, #1107): the large-title row of a main screen follows the list look (`ScreenLargeTitle`).
    func listLookTitleRow() -> some View { modifier(DenseTitleRow()) }

    /// EXPERIMENTAL(denseRows, #1107): a category row's vertical insets in the dense look; the classic look keeps the system's.
    func denseCategoryRowInsets(_ look: ListLook) -> some View {
        listRowInsets(.vertical, look == .dense ? DenseListLook.categoryRowVerticalInset : nil)
    }
}
