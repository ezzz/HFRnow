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

    /// Outer side margin (screen edge to card) of an inset-grouped list: nil keeps the system's (about 20 pt), compact halves it.
    var outerMargin: CGFloat? {
        switch self {
        case .regular: nil
        case .compact: 10
        }
    }

    /// System inner side inset of an inset-grouped row and of its section header.
    static let systemInnerMargin: CGFloat = 16

    /// How far the density moves a system-inset row sideways (negative: towards the card edge).
    var innerMarginShift: CGFloat { rowInsets.leading - Self.systemInnerMargin }

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

    /// One meta line (who · last post) instead of two in a conversation row.
    var mergesMetaLines: Bool { self == .compact }
}

extension EnvironmentValues {
    /// The density of every list; the app root sets it from the "Mode compact" setting.
    @Entry var listDensity = ListDensity.regular
}

/// Sets the outer side margin of a list from the density; a nil margin is the system layout, so the list keeps its identity
/// (scroll position, row state) when the density changes.
private struct DensityListMargins: ViewModifier {
    @Environment(\.listDensity) private var density

    func body(content: Content) -> some View {
        content.contentMargins(.horizontal, density.outerMargin, for: .scrollContent)
    }
}

/// Moves a row's or a section header's content from the system's inner side inset to the density's.
private struct DensityInnerMargin: ViewModifier {
    @Environment(\.listDensity) private var density

    func body(content: Content) -> some View {
        content.padding(.horizontal, density.innerMarginShift)
    }
}

extension View {
    /// Makes an inset-grouped list's outer side margin follow the density (#799); the rows' inner margin is `rowInsets`.
    /// Only for `.insetGrouped` lists: on a plain list the margin would leave the row backgrounds short of the screen edge.
    func densityListMargins() -> some View { modifier(DensityListMargins()) }

    /// Aligns a row (or a section header) that keeps the system's inset with the rows that read `rowInsets` (#799).
    func densityInnerMargin() -> some View { modifier(DensityInnerMargin()) }

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
