/// The `theme_style` setting: message rendering style.
public enum ThemeStyle: Int, Sendable, Codable, CaseIterable {
    /// Classic style.
    case classic = 0
    /// Modern style (default).
    case modern = 1
}
