import CoreGraphics
import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// Noël abusé (LOT-166 PR 4, THEMES.md §2, §5): a single-variant theme of the engine, picked by hand inside the window, stored
/// as the season's Noël theme, drawn over whatever the user's theme is, packed and restored like Noël soft.
@MainActor
struct NoelAbuseTests {
    /// The bundled theme file, as the app reads it.
    private func noelAbuse() throws -> ThemeDefinition {
        try #require(ThemeCatalog.bundled.themes.first { $0.id == SeasonalTheme.noelAbuse.rawValue })
    }

    /// The test theme and the bundled Noël abusé file (Legacy is built in when its file is not given).
    private func catalogWithNoelAbuse() throws -> ThemeCatalog {
        let url = try #require(Bundle.main.url(forResource: "noel-abuse.theme", withExtension: "json"))
        return ThemeCatalog(files: [
            ("test-theme.theme.json", try ThemeFixtures.data("test-theme")), ("noel-abuse.theme.json", try Data(contentsOf: url))
        ])
    }

    @Test func theThemeFileIsBundledInTheNoelFamilyWithOneVariantAndItsArt() throws {
        let theme = try noelAbuse()
        #expect(theme.name == "Noël abusé")
        #expect(theme.family == "Noël")
        #expect(theme.fontDesign == .rounded)
        #expect(theme.decorations == SeasonalTheme.noelAbuseDecorations)
        guard case .single? = theme.variants else {
            Issue.record("Noël abusé is « clair = sombre »")
            return
        }
        // A seasonal family: never in the gallery, only in « Thèmes de saison » inside the window.
        #expect(!ThemeCatalog.bundled.galleryFamilies.contains { $0.family == "Noël" })
    }

    @Test func pickingItInsideTheWindowStoresItAndSavesTheUsersTheme() {
        let clock = SeasonTestClock(10, 12, 2026)
        let store = InMemorySettingsStore()
        let model = clock.model(store: store)
        model.sceneDidBecomeActive()
        model.answerArrival(disable: true)
        model.select(.noelAbuse)
        #expect(model.activeTheme == .noelAbuse)
        #expect(store.value(for: SettingKey.noelThemeID(year: 2026)) == "noel-abuse")
        #expect(store.value(for: SettingKey.noelPreviousThemeID(year: 2026)) == ThemeDefinition.legacyID)
        #expect(!model.snowFalls)
        // A relaunch finds it on.
        clock.move(to: 11, 12, 2026)
        #expect(clock.model(store: store).activeTheme == .noelAbuse)
    }

    /// From Noël soft to Noël abusé and back: the theme saved when Noël soft was switched on stays the one restored.
    @Test func movingBetweenTheNoelThemesKeepsTheSavedTheme() {
        let clock = SeasonTestClock(1, 12, 2026)
        let store = InMemorySettingsStore()
        store.set("test-theme", for: SettingKey.themeID)
        let model = clock.model(store: store)
        model.sceneDidBecomeActive()
        #expect(model.activeTheme == .noelSoft)
        store.set("another-theme", for: SettingKey.themeID)
        model.select(.noelAbuse)
        #expect(model.activeTheme == .noelAbuse)
        model.select(.noelSoft)
        #expect(model.activeTheme == .noelSoft)
        #expect(store.value(for: SettingKey.noelPreviousThemeID(year: 2026)) == "test-theme")
        model.select(nil)
        #expect(model.activeTheme == nil)
        #expect(store.value(for: SettingKey.noelThemeID(year: 2026)) == nil)
        #expect(store.value(for: SettingKey.noelPreviousThemeID(year: 2026)) == nil)
    }

    /// A season switched on by a build before PR 4 has no `themeID`: Noël soft; an id this build does not know reads the same.
    @Test(arguments: [nil, "noel-futur"])
    func aMissingOrUnknownThemeIDReadsAsNoelSoft(stored: String?) {
        let clock = SeasonTestClock(10, 12, 2026)
        let store = InMemorySettingsStore()
        store.set(ThemeDefinition.legacyID, for: SettingKey.noelPreviousThemeID(year: 2026))
        store.set(2026, for: SettingKey.noelActiveYear)
        store.set(stored, for: SettingKey.noelThemeID(year: 2026))
        #expect(clock.model(store: store).activeTheme == .noelSoft)
    }

    @Test func itCannotBePickedOutsideTheWindow() {
        let clock = SeasonTestClock(27, 12, 2026)
        let store = InMemorySettingsStore()
        let model = clock.model(store: store)
        model.select(.noelAbuse)
        #expect(model.activeTheme == nil)
        #expect(store.value(for: SettingKey.noelThemeID(year: 2026)) == nil)
    }

    /// The first launch 27/12: the elves pack Noël abusé, which stays drawn until they are done; the store is clean at once.
    @Test func packingTakesNoelAbuseDown() throws {
        let clock = SeasonTestClock(10, 12, 2026)
        let store = InMemorySettingsStore()
        let first = clock.model(store: store)
        first.select(.noelAbuse)
        clock.move(to: 27, 12, 2026)
        let model = clock.model(store: store)
        #expect(model.sceneDidBecomeActive() == [.packed(year: 2026, animated: true)])
        #expect(store.value(for: SettingKey.noelThemeID(year: 2026)) == nil)
        #expect(model.activeTheme == nil)
        #expect(try #require(model.packing.current).theme == .noelAbuse)
        #expect(model.drawnTheme == .noelAbuse)
        model.packing.finish()
        #expect(model.drawnTheme == nil)
    }

    @Test func aThemeLeftOnIsRestoredSilentlyWithItsID() {
        let clock = SeasonTestClock(10, 12, 2026)
        let store = InMemorySettingsStore()
        clock.model(store: store).select(.noelAbuse)
        clock.move(to: 5, 2, 2027)
        let model = clock.model(store: store)
        #expect(model.activeTheme == nil)
        #expect(model.sceneDidBecomeActive() == [.restoredSilently(year: 2026)])
        #expect(store.value(for: SettingKey.noelThemeID(year: 2026)) == nil)
    }

    // MARK: Appearance

    /// Over Legacy or a gallery theme, Noël abusé's tokens, font and art replace the theme drawn; the stored keys stay.
    @Test(arguments: [false, true])
    func itsTokensReplaceTheUsersTheme(gallery: Bool) throws {
        let store = InMemorySettingsStore()
        let catalog = try catalogWithNoelAbuse()
        let model = ThemeSettingsModel(store: store, catalog: catalog)
        if gallery { model.select(try #require(catalog.themes.first { $0.id == "test-theme" })) }
        let stored = store.value(for: SettingKey.themeID)
        let noel = model.appearance.applying(.noelAbuse, catalog: catalog)
        let theme = try noelAbuse()
        guard case let .single(tokens)? = theme.variants else {
            Issue.record("Noël abusé is single-variant")
            return
        }
        #expect(noel.themeVariants == theme.variants)
        #expect(noel.themeDecorations == SeasonalTheme.noelAbuseDecorations)
        #expect(noel.fontDesign == .rounded)
        // Fir green imposes the dark appearance (« clair = sombre »), whatever the « Thème » picker says.
        #expect(noel.forcedColorScheme == .dark)
        #expect(noel.screenFill == .theme(light: tokens.background, dark: tokens.background))
        // Drawn over the user's theme, never stored.
        #expect(store.value(for: SettingKey.themeID) == stored)
        #expect(model.appearance.applying(nil, catalog: catalog) == model.appearance)
    }

    /// The window takes the scheme the drawn theme imposes: Noël abusé is dark even for a « Clair » user, whose own scheme comes
    /// back with Noël soft or no seasonal theme (`appTheme` reads `colorScheme(drawing:)`).
    @Test func noelAbuseImposesTheDarkSchemeOverTheUsersChoice() throws {
        let catalog = try catalogWithNoelAbuse()
        let model = ThemeSettingsModel(store: InMemorySettingsStore(), catalog: catalog)
        model.mode = .light
        #expect(model.colorScheme(drawing: model.appearance.applying(.noelAbuse, catalog: catalog)) == .dark)
        #expect(model.colorScheme(drawing: model.appearance.applying(.noelSoft, catalog: catalog)) == .light)
        #expect(model.colorScheme(drawing: model.appearance) == .light)
        model.mode = .system
        #expect(model.colorScheme(drawing: model.appearance) == nil)
    }

    /// A build whose bundle lacks the file draws the user's theme unchanged rather than a half theme.
    @Test func withoutItsFileTheUsersThemeIsDrawn() throws {
        let catalog = try ThemeFixtures.catalog()
        let model = ThemeSettingsModel(store: InMemorySettingsStore(), catalog: catalog)
        #expect(model.appearance.applying(.noelAbuse, catalog: catalog) == model.appearance)
    }

    /// The art is drawn at `artOpacity`: even a white pixel there keeps the text native screens draw on the background ≥ 4.5:1
    /// (rule 7): the system label and secondary label of the dark appearance Noël abusé imposes (section headers and footers
    /// are the secondary label, 60 % of #EBEBF5), and the tint.
    @Test func theArtKeepsTheTextOnTheBackgroundReadable() throws {
        guard case let .single(tokens)? = try noelAbuse().variants else {
            Issue.record("Noël abusé is single-variant")
            return
        }
        let white = ThemeRGB(red: 255, green: 255, blue: 255)
        let underArt = tokens.background.mixed(with: white, amount: NoelAbuseLayout.artOpacity)
        let secondaryLabel = underArt.mixed(with: ThemeRGB(red: 235, green: 235, blue: 245), amount: 0.6)
        for text in [white, secondaryLabel, tokens.accentText] {
            #expect(underArt.contrast(with: text) >= 4.5, "\(text)")
        }
    }
}

/// Where Noël abusé's art sits (`NoelAbuseLayout`).
struct NoelAbuseLayoutTests {
    @Test(arguments: [CGSize(width: 402, height: 874), CGSize(width: 1024, height: 1366), CGSize(width: 320, height: 568)])
    func everyPieceStaysOnTheScreen(size: CGSize) throws {
        let screen = CGRect(origin: .zero, size: size)
        for star in NoelAbuseLayout.stars(in: size) { #expect(screen.contains(star)) }
        let garland = NoelAbuseLayout.garland(in: size, topInset: 59)
        #expect(garland.first?.minX == 0)
        #expect((garland.last?.maxX ?? 0) >= size.width)
        #expect(garland.allSatisfy { $0.minY == 59 })
        let tree = try #require(NoelAbuseLayout.tree(in: size, bottomInset: 34))
        #expect(screen.contains(tree))
        #expect(tree.maxY == size.height - 34)
        #expect(tree.height <= NoelAbuseLayout.maxTreeHeight)
        #expect(tree.height >= NoelAbuseLayout.minTreeHeight)
        let ornaments = NoelAbuseLayout.ornaments(in: size, topInset: 59)
        #expect(!ornaments.isEmpty)
        for ornament in ornaments {
            #expect(screen.contains(ornament))
            #expect(ornament.minY == 59 + NoelAbuseLayout.garlandHeight)
        }
        let gifts = NoelAbuseLayout.gifts(in: size, bottomInset: 34)
        #expect(gifts.count == 3)
        for gift in gifts {
            #expect(screen.contains(gift))
            #expect(!gift.intersects(tree))
            #expect(gift.maxY == tree.maxY)
        }
    }

    @Test func anEmptyOrNarrowScreenHasNoArt() {
        #expect(NoelAbuseLayout.stars(in: .zero).isEmpty)
        #expect(NoelAbuseLayout.garland(in: .zero, topInset: 0).isEmpty)
        #expect(NoelAbuseLayout.ornaments(in: .zero, topInset: 0).isEmpty)
        #expect(NoelAbuseLayout.tree(in: CGSize(width: 50, height: 874), bottomInset: 0) == nil)
        #expect(NoelAbuseLayout.gifts(in: CGSize(width: 50, height: 874), bottomInset: 0).isEmpty)
    }

    /// Static art, drawn once per size: the star pattern stays small on the largest iPad.
    @Test func theStarPatternIsBounded() {
        let stars = NoelAbuseLayout.stars(in: CGSize(width: 1366, height: 1024))
        #expect(stars.count <= 22 * 17)
        #expect(!stars.isEmpty)
    }
}
