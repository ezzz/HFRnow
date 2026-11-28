import SwiftUI

/// The light rim Samain's art gets on a dark scheme (THEMES.md §4 rule 7): the purple witch and vampire measure about 2.3:1 against
/// Spooktober soft's dark background, so a thin white outline keeps their silhouette ≥ 3:1 (WCAG 1.4.11) while the art itself is
/// unchanged. Light schemes get none. A Gaussian shadow of radius 1.5 pt (the Fête nationale's) is ≥ 3:1 over 0.33 pt only, rendered
/// at 3x over `#121014` (review of #1441), and weaker still beside the vampire's thin spikes; the outline is four hard shadows
/// (radius 0) stacked, each one taken on the result of the last, so together they dilate the silhouette by `outline` points in every
/// direction. `SamainDecorationTests` renders every sprite and measures the pixels next to it.
nonisolated enum SamainRim {
    /// The outline's opacity (it fades a little with each stacked shadow) and thickness, in points.
    static let opacity = 0.95
    static let outline: CGFloat = 1.5
}

extension View {
    /// The art with its rim on a dark scheme; `enabled` false (Noël's art, the abusé art drawn at 14 %) draws it plainly.
    func samainRim(_ scheme: ColorScheme, enabled: Bool = true) -> some View {
        let halo = enabled && scheme == .dark ? Color.white.opacity(SamainRim.opacity) : .clear
        let reach = SamainRim.outline
        return shadow(color: halo, radius: 0, x: reach, y: 0)
            .shadow(color: halo, radius: 0, x: -reach, y: 0)
            .shadow(color: halo, radius: 0, x: 0, y: reach)
            .shadow(color: halo, radius: 0, x: 0, y: -reach)
    }
}
