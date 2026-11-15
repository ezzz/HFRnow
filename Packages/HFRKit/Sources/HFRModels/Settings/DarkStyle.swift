/// The `theme_dark_style` setting (LOT-122, new, no legacy key): how dark the dark theme's surfaces are.
public enum DarkStyle: Int, Sendable, Codable, CaseIterable {
    /// The colours the app always had (default).
    case standard = 0
    /// Near-black surfaces (#0B0B0C), softer than OLED black.
    case darker = 1
    /// Pure black screens, for OLED displays.
    case oled = 2
}
