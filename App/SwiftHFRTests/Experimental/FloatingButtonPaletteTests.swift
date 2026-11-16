import HFRStorage
import SwiftUI
@testable import SwiftHFR
import Testing

/// The modern composer's floating buttons stay readable over any page (#972): the glyph against its capsule laid over the
/// lightest and the darkest page, in each scheme. A page's colour mixes into the capsule linearly, so white and black bound
/// every other page.
struct FloatingButtonPaletteTests {
    private static let pages = [ThemeColor(hex: 0xFFFFFF), ThemeColor(hex: 0x000000)]

    /// WCAG 2 text contrast (4.5:1), stricter than the 3:1 a non-text control needs.
    @Test(arguments: [ColorScheme.light, .dark])
    func theGlyphIsReadableOverAnyPage(scheme: ColorScheme) {
        let palette = FloatingButtonPalette(scheme: scheme)
        for page in Self.pages {
            let capsule = palette.fill.composited(over: page)
            #expect(palette.glyph.contrast(with: capsule) >= 4.5, "\(scheme) over \(page)")
        }
    }

    /// Where the capsule meets the composer's own fill (a sheet's opaque background, the docked bar under the row at full
    /// height): the system background, white in light and black in dark, already among `pages`; checked by name so a palette
    /// change cannot drop it.
    @Test func theGlyphIsReadableOverTheComposersOwnBackground() {
        let light = FloatingButtonPalette(scheme: .light)
        #expect(light.glyph.contrast(with: light.fill.composited(over: ThemeColor(hex: 0xFFFFFF))) >= 4.5)
        let dark = FloatingButtonPalette(scheme: .dark)
        #expect(dark.glyph.contrast(with: dark.fill.composited(over: ThemeColor(hex: 0x000000))) >= 4.5)
    }

    /// The docked bar's fill starts under the buttons' row at partial height, so the page shows around them (#972); at full
    /// height the bar covers the page from its top.
    @Test func theDockedBarLeavesTheButtonsRowUnfilledAtPartialHeight() {
        #expect(DockedComposerBar.fillStart(height: .partial, buttonsHeight: 60) == 60)
        #expect(DockedComposerBar.fillStart(height: .full, buttonsHeight: 60) == 0)
        #expect(DockedComposerBar.fillStart(height: .partial, buttonsHeight: 0) == 0, "before the first measure")
    }

    /// The capsule hides most of the page under it: "slightly more visible" than the bare glass it replaces (#972).
    @Test(arguments: [ColorScheme.light, .dark])
    func theCapsuleHidesMostOfThePage(scheme: ColorScheme) {
        #expect(FloatingButtonPalette(scheme: scheme).fill.alpha >= 0.8)
    }

    @Test func compositingMixesByAlpha() {
        let half = ThemeColor(red: 1, green: 1, blue: 1, alpha: 0.5).composited(over: ThemeColor(hex: 0x000000))
        #expect(half == ThemeColor(red: 0.5, green: 0.5, blue: 0.5))
    }
}
