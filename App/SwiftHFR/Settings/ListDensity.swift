import SwiftUI

// Port of HFRswift/Swift/Favorites.swift (FavoritesListDensity, :188-215) and Common.swift (compact_mode :228,
// compactListSectionSpacing :309) @ 21173e77. Differences: every list follows the setting, not only the favourites and the
// settings; compact rows also shorten the title, merge the meta lines and shrink the markers (LOT-169). Deliberate gap
// (#799): legacy's inset-grouped lists keep wide side margins (`Favorites.swift:429` @ 87fe0d1c); compact halves them here.
/// The density of every list: regular rows, or compact rows (`compact_mode`) that show more of a list per screen.
enum ListDensity: Sendable {
    case regular
    case compact

    /// The density of the "Mode compact" setting.
    init(compactMode: Bool) {
        self = compactMode ? .compact : .regular
    }

    /// Row insets: legacy's favourites row (list inset 4 + content padding 2) in regular rows; compact rows halve the
    /// inner side margin (#799).
    var rowInsets: EdgeInsets {
        switch self {
        case .regular: EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        case .compact: EdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7)
        }
    }

    /// Outer side margin of an inset-grouped list: the distance from the safe-area edge to the card. Nil keeps the system's
    /// (about 20 pt), compact halves it.
    var outerMargin: CGFloat? {
        switch self {
        case .regular: nil
        case .compact: 10
        }
    }

    /// The inner side inset set on a row that keeps the system's vertical insets: nil in regular rows (the system's), the
    /// compact inner margin otherwise.
    var rowSideInset: CGFloat? { outerMargin == nil ? nil : rowInsets.leading }

    /// Space between list sections (legacy compact favourites: 6).
    var sectionSpacing: ListSectionSpacing {
        switch self {
        case .regular: .default
        case .compact: .custom(6)
        }
    }

    /// Minimum row height, before Dynamic Type: the system's 44 in regular rows.
    var minimumRowHeight: CGFloat {
        switch self {
        case .regular: 44
        case .compact: 28
        }
    }

    /// Text style of a row's title: legacy's favourites title is 14.3 pt at the default size (`Favorites.swift:1121`), close
    /// to the subheadline's 15; compact rows go one step down.
    var titleStyle: Font.TextStyle {
        switch self {
        case .regular: .subheadline
        case .compact: .footnote
        }
    }

    /// Most lines of a topic or conversation title.
    var titleLineLimit: Int {
        switch self {
        case .regular: 3
        case .compact: 2
        }
    }

    /// Vertical space between a row's lines.
    var lineSpacing: CGFloat {
        switch self {
        case .regular: 2
        case .compact: 0
        }
    }

    /// Diameter of the unread dot, before Dynamic Type and the type scale.
    var markerSize: CGFloat {
        switch self {
        case .regular: 8
        case .compact: 6
        }
    }

    /// Side of a conversation's avatar, before Dynamic Type and the type scale.
    var avatarSize: CGFloat {
        switch self {
        case .regular: 40
        case .compact: 28
        }
    }
}

extension EnvironmentValues {
    /// The density of every list; the app root sets it from the "Mode compact" setting.
    @Entry var listDensity = ListDensity.regular
    /// Window x of the left edge of the cards of the enclosing list (set by `densityListMargins`).
    @Entry var densityCardEdge: CGFloat = 0
}

/// Sets the outer side margin of a list from the density; a nil margin is the system layout, so the list keeps its identity
/// (scroll position, row state) when the density changes. Also tells the headers where the cards start, in window coordinates:
/// a section header is hosted apart from the list, so a coordinate space named on the list never reaches it (measured, #979).
///
/// #832: a scroll content margin replaces the system's side inset, safe area included, so in landscape the card slid under
/// the notch while its rows kept the safe area inside it. The margins add the safe inset back; the list's frame already starts
/// past it (measured: x = 62 under a 62 pt left inset), so the card edge is the frame's x plus the margin, nothing more.
private struct DensityListMargins: ViewModifier {
    @Environment(\.listDensity) private var density
    @State private var safeLeading: CGFloat = 0
    @State private var safeTrailing: CGFloat = 0
    @State private var originX: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .contentMargins(.leading, density.outerMargin.map { $0 + safeLeading }, for: .scrollContent)
            .contentMargins(.trailing, density.outerMargin.map { $0 + safeTrailing }, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.leading } action: { safeLeading = $0 }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.trailing } action: { safeTrailing = $0 }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { originX = $0 }
            .environment(\.densityCardEdge, originX + (density.outerMargin ?? 0))
    }
}

/// Sets the inner side inset of a row that keeps the system's vertical insets (nil in regular rows: the system's).
private struct DensityRowMargin: ViewModifier {
    @Environment(\.listDensity) private var density

    func body(content: Content) -> some View {
        content.listRowInsets(.horizontal, density.rowSideInset)
    }
}

/// Moves a section header's content onto the density's inner margin. A header takes the system's inset, whatever it is
/// (16 pt, 20 pt in wide columns): the modifier measures where the header starts and moves it from there.
///
/// #979: both ends are window x, so a list moved as a whole (the parallax of a pushed screen) keeps its shift. The shift is also
/// capped: it measures the view it pads, so a shift that squeezed the header past its content would move what it measures, and
/// the header would chase itself forever on the main thread (the Favoris freeze, compact density, list under a pushed screen).
private struct DensityHeaderMargin: ViewModifier {
    @Environment(\.listDensity) private var density
    @Environment(\.densityCardEdge) private var cardEdge
    @State private var systemX: CGFloat?

    /// The most a header moves: the system's header inset (16 or 20 pt) is the whole distance to the card's inner margin.
    static let maximumShift: CGFloat = 20

    /// The move from the header's measured start `systemX` to `target`, within `maximumShift`.
    static func shift(from systemX: CGFloat, to target: CGFloat) -> CGFloat {
        min(max(target - systemX, -maximumShift), maximumShift)
    }

    func body(content: Content) -> some View {
        let shift = systemX.flatMap { x in density.rowSideInset.map { Self.shift(from: x, to: cardEdge + $0) } } ?? 0
        content
            .padding(.horizontal, shift)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { systemX = $0 }
    }
}

extension View {
    /// Makes an inset-grouped list's outer side margin follow the density (#799); the rows' inner margin is `rowInsets`.
    /// Only for `.insetGrouped` lists: on a plain list the margin would leave the row backgrounds short of the screen edge.
    func densityListMargins() -> some View { modifier(DensityListMargins()) }

    /// Puts a row that keeps the system's vertical insets on the density's inner margin (#799); rows with their own
    /// `listRowInsets(density.rowInsets)` already are.
    func densityRowMargin() -> some View { modifier(DensityRowMargin()) }

    /// Aligns a section header's text with the rows' (#799).
    func densityHeaderMargin() -> some View { modifier(DensityHeaderMargin()) }

    /// Applies the type scale and the list density to every screen below (LOT-169): the default font, the row height and
    /// the section spacing of every list, and the environment values rows and the reader read.
    func appTypography(_ scale: TextScale, density: ListDensity) -> some View {
        scaledFont(.body)
            .listSectionSpacing(density.sectionSpacing)
            .environment(\.defaultMinListRowHeight, density.minimumRowHeight)
            .environment(\.listDensity, density)
            .environment(\.textScale, scale)
    }
}
