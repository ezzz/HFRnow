import SwiftUI

/// A state tint for a list row: a few percent of `tint` layered over the row's real background, so the system
/// colour stays underneath (a bare translucent `listRowBackground` would replace it) (#570).
struct RowTint: View {
    /// The list style the row sits in, which decides the colour underneath.
    enum Base {
        case grouped, plain

        fileprivate var color: Color {
            switch self {
            case .grouped: Color(.secondarySystemGroupedBackground)
            case .plain: Color(.systemBackground)
            }
        }
    }

    var tint: Color = .accentColor
    var base: Base = .grouped
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        base.color.overlay(tint.opacity(Self.strength(scheme: scheme, contrast: contrast)))
    }

    /// Opacity of the tint: stronger in dark, where the same alpha reads weaker, and again with Increase Contrast.
    static func strength(scheme: ColorScheme, contrast: ColorSchemeContrast) -> Double {
        (scheme == .dark ? 0.16 : 0.10) + (contrast == .increased ? 0.08 : 0)
    }
}
