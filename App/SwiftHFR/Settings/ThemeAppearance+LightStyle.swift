import HFRModels
import SwiftUI

/// The light style of the Legacy theme (#1213) and what the « Thème » tiles draw. « Blanc » is today's light look and sends and
/// paints nothing; « Doux » is a warm, low-glare light look.
extension ThemeAppearance {
    /// The background of every screen in the light theme, or nil for the system's (« Blanc »).
    var lightScreenBackground: ThemeColor? {
        switch lightStyle {
        case .blanc: nil
        case .doux: Self.douxPage
        }
    }

    /// « Doux »'s page: an off-white, warmer than white (#1213, validated on the PR's screenshot).
    static let douxPage = ThemeColor(hex: 0xF5F4EF)
    /// The `--app-light-*` variables of the light style: none for « Blanc » (the page keeps its own fallbacks), five for « Doux ».
    /// The secondary text is a notch darker than the system's so it keeps 4.5:1 on the warm surfaces (folded quote, classic
    /// header included, `ThemeLightStyleTests`).
    var lightSurfaces: [(variable: String, color: ThemeColor)] {
        switch lightStyle {
        case .blanc: []
        case .doux:
            [("--app-light-background", Self.douxPage), ("--app-light-quote-background", ThemeColor(hex: 0xEDEBE3)),
             ("--app-light-placeholder", ThemeColor(hex: 0xE9E7DE)), ("--app-light-separator", ThemeColor(hex: 0xD6D3C8)),
             ("--app-light-secondary", ThemeColor(hex: 0x636366))]
        }
    }

    /// The names of the light variables, to take off the page when the style goes back to « Blanc ».
    static let lightVariableNames = [
        "--app-light-background", "--app-light-quote-background", "--app-light-placeholder", "--app-light-separator",
        "--app-light-secondary"
    ]

    /// What a « Thème » tile draws for the light or the dark variant (#1213): the surface the reader shows (the light style's page,
    /// the dark style's page at the chosen brightness, or a gallery theme's `surface`), a secondary-text colour for its two lines,
    /// and the chosen accent for its dot, so the tiles follow the hue slider live.
    struct TileLook: Equatable {
        /// The page of the mock screen.
        var surface: ThemeColor
        /// The two text lines.
        var line: ThemeColor
        /// The accent dot.
        var dot: ThemeColor
    }

    /// The look of the tile's light or dark half.
    func tileLook(dark: Bool) -> TileLook {
        if let variants = themeVariants {
            let tokens = dark ? variants.dark : variants.light
            return TileLook(
                surface: ThemeColor(rgb: tokens.surface), line: ThemeColor(rgb: tokens.textSecondary),
                dot: ThemeColor(rgb: tokens.accentText)
            )
        }
        if dark {
            let page = readerSurfaces.first { $0.variable == "--app-dark-background" }?.color ?? ThemeColor(hex: 0)
            return TileLook(surface: page, line: Self.darkSecondaryText, dot: nightAccent)
        }
        let secondary = lightSurfaces.first { $0.variable == "--app-light-secondary" }?.color ?? ThemeColor(hex: 0x6C6C70)
        return TileLook(surface: lightScreenBackground ?? ThemeColor(hex: 0xFFFFFF), line: secondary, dot: dayAccent)
    }
}
