import HFRModels
import HFRStorage

// Port of HFRswift/Swift/Common.swift (ThemeUserColorStore.actionTintColor, dynamicActionTintColor: `.red` while
// theme_noel_disabled is off, `:610-612, 625-627`) @ 87fe0d1c. Differences: drawn over the user's colours, never stored (GAP-147).
extension ThemeAppearance {
    /// Legacy's Christmas accent, `UIColor.red` in both variants.
    static let noelAccent = ThemeColor(red: 1, green: 0, blue: 0)

    /// The appearance with `seasonal` drawn over it: Noël soft takes legacy's red accent and keeps the rest (dark style,
    /// brightness). The user's own values stay in the store, so turning the theme off gives them back unchanged. Over a gallery
    /// theme (LOT-188) the accent is the theme's `accentText`, which this leaves alone: the theme keeps its accent and gets the
    /// snow and the crossings (operator decision (a), 2026-11-12, THEMES.md §5). Noël abusé and the two Spooktober themes
    /// (LOT-191) are themes of the engine (`catalog`'s `noel-abuse`, `spooktober-soft`, `spooktober-abuse`): their tokens, font
    /// design and art replace the user's theme, whatever it is, which stays stored; a build without the file draws the user's
    /// theme unchanged.
    func applying(_ seasonal: SeasonalTheme?, catalog: ThemeCatalog = .bundled) -> ThemeAppearance {
        guard let seasonal else { return self }
        guard seasonal.isEngineTheme else {
            // Noël soft, decision (a): over a gallery theme nothing changes; the theme keeps its accent and the reader no red
            // --app-action-*.
            guard themeVariants == nil else { return self }
            var copy = self
            copy.dayAccent = Self.noelAccent
            copy.nightAccent = Self.noelAccent
            return copy
        }
        guard let theme = catalog.themes.first(where: { $0.id == seasonal.rawValue }), theme.variants != nil else { return self }
        var copy = self
        copy.themeVariants = theme.variants
        copy.themeFontDesign = theme.fontDesign
        copy.themeDecorations = theme.decorations
        return copy
    }
}
