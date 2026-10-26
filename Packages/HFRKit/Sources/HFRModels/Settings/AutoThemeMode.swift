/// The `auto_theme` setting; legacy raw values (any other stored value means `.system`, normalised by the settings store).
public enum AutoThemeMode: Int, Sendable, Codable, CaseIterable {
    /// The user picks `ThemeVariant` manually.
    case manual = 0
    /// Follow the system appearance.
    case system = 3
}
