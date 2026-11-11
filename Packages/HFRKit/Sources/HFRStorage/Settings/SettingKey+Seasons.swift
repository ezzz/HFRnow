extension SettingKey {
    /// `season.noel.<year>.arrivalShown` (LOT-166, new): the Noël arrival of that season was shown (THEMES.md §5).
    public static func noelArrivalShown(year: Int) -> Setting<Bool> { .bool(noelKey(year, "arrivalShown"), default: false) }
    /// `season.noel.<year>.optedOut`: the user answered « Désactiver » that season.
    public static func noelOptedOut(year: Int) -> Setting<Bool> { .bool(noelKey(year, "optedOut"), default: false) }
    /// `season.noel.<year>.previousThemeID`: the theme a Noël theme replaced; present while a Noël theme of that season is on.
    public static func noelPreviousThemeID(year: Int) -> Setting<String?> { .optionalString(noelKey(year, "previousThemeID")) }
    /// `season.noel.<year>.packingShown`: the packing of that season ran.
    public static func noelPackingShown(year: Int) -> Setting<Bool> { .bool(noelKey(year, "packingShown"), default: false) }

    /// The Noël keys of one season. They stay out of `all`, which lists fixed keys; all are device-only (ADR 0013 matrix E).
    public static func noelSeason(year: Int) -> [any CatalogueSetting] {
        [noelArrivalShown(year: year), noelOptedOut(year: year), noelPreviousThemeID(year: year), noelPackingShown(year: year)]
    }

    /// A season's year is the year of its December: the Noël of December 2026 ends in January 2027 under the 2026 keys.
    private static func noelKey(_ year: Int, _ name: String) -> String { "season.noel.\(year).\(name)" }
}
