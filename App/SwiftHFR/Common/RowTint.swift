import SwiftUI

/// A state tint for a list row: a few percent of `tint` layered over the row's real background, so the system
/// colour stays underneath (a bare translucent `listRowBackground` would replace it) (#570).
struct RowTint: View {
    /// The list style the row sits in, which decides the colour underneath.
    enum Base: Equatable {
        case grouped, plain
        /// Nothing underneath: the tint alone, as a bare translucent row background (sidebar rows have no card colour).
        case clear

        fileprivate var color: Color {
            switch self {
            case .grouped: Color(.secondarySystemGroupedBackground)
            case .plain: Color(.systemBackground)
            case .clear: Color.clear
            }
        }
    }

    var tint: Color = .accentColor
    /// Multiplies the strength, for a quieter tint.
    var weight = 1.0
    var base: Base = .grouped
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        base.color.overlay(tint.opacity(Self.strength(scheme: scheme, contrast: contrast, weight: weight)))
    }

    /// Opacity of the tint: stronger in dark, where the same alpha reads weaker, and again with Increase Contrast.
    static func strength(scheme: ColorScheme, contrast: ColorSchemeContrast, weight: Double = 1) -> Double {
        ((scheme == .dark ? 0.16 : 0.10) + (contrast == .increased ? 0.08 : 0)) * weight
    }
}
