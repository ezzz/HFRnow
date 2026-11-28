import SwiftUI

/// The light rim Samain's art gets on a dark scheme (THEMES.md §4 rule 7, as the Fête nationale bursts): the purple witch and
/// vampire measure about 2.3:1 against Spooktober soft's dark background, so a thin white halo keeps their silhouette ≥ 3:1
/// (WCAG 1.4.11) while the art itself is unchanged. Light schemes get none.
nonisolated enum SamainRim {
    /// The halo's opacity and blur radius, in points.
    static let opacity = 0.85
    static let radius: CGFloat = 1.5
}

extension View {
    /// The art with its rim on a dark scheme; `enabled` false (Noël's art, the abusé art drawn at 14 %) draws it plainly.
    func samainRim(_ scheme: ColorScheme, enabled: Bool = true) -> some View {
        shadow(color: enabled && scheme == .dark ? .white.opacity(SamainRim.opacity) : .clear, radius: SamainRim.radius)
    }
}
