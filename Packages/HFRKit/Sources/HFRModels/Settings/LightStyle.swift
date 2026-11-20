/// The `theme_light_style` setting (#1213, new, no legacy key): how the light theme's surfaces look. Legacy has one light look.
public enum LightStyle: Int, Sendable, Codable, CaseIterable {
    /// The light look the app always had: white surfaces (default).
    case blanc = 0
    /// Warm, low-glare surfaces: an off-white page instead of pure white.
    case doux = 1
}
