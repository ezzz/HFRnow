import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing
import UIKit

/// The "Thème" colours in the real reader (LOT-121): the window's scheme picks the variant, the app's accent and dark
/// brightness reach the page from the first render, then live without a reload.
@MainActor
@Suite(.serialized)
struct ReaderThemeTests: ReaderWebTesting {
    /// Computed colours of a link and of a quote added to the shown page.
    private let probe = """
        const link = document.createElement('a'); link.href = '#'; document.body.appendChild(link);
        const quote = document.createElement('table'); quote.className = 'quote'; document.body.appendChild(quote);
        const result = [getComputedStyle(link).color, getComputedStyle(quote).backgroundColor];
        link.remove(); quote.remove();
        return result.join('|');
        """

    /// The scaled `--placeholder` surface (it follows the dark brightness; the default quote no longer does, #819).
    private func placeholder(in controller: ReaderWebController) async -> String {
        let script = """
            const probe = document.createElement('div'); probe.style.background = 'var(--placeholder)'; document.body.appendChild(probe);
            const result = getComputedStyle(probe).backgroundColor; probe.remove(); return result;
            """
        return ((try? await evaluate(script, in: controller)) as? String) ?? ""
    }

    private func colours(in controller: ReaderWebController) async -> String {
        ((try? await evaluate(probe, in: controller)) as? String) ?? ""
    }

    /// The default look has no quote or code fill (#819, legacy `style-liste.css:329-334`); only a gallery theme brings one.
    private let none = "rgba(0, 0, 0, 0)"
    private let red = ThemeColor(red: 1, green: 0, blue: 0)
    private let blue = ThemeColor(red: 0, green: 0, blue: 1)

    @Test func theDarkVariantGetsTheNightAccentAndTheScaledSurfacesThenFollowsAChangeLive() async {
        let (controller, recorder) = makeController(transport: imageTransport())
        recorder.window?.overrideUserInterfaceStyle = .dark
        controller.theme = ThemeAppearance(dayAccent: red, nightAccent: blue, darkBrightness: 0)
        controller.show(document(token: 1))
        #expect(await until { recorder.ready == [1] }, "ready: \(recorder.ready)")
        // The dark surfaces scale (at 0 % they are black; the standard grey is 0x2E2F33) but the default quote has no fill (#819).
        let expected = "rgb(0, 0, 255)|\(none)"
        let first = await until(async: { await colours(in: controller) == expected })
        let seen = await colours(in: controller)
        #expect(first, "colours: \(seen)")
        // 0x35363B at 0 %: black.
        let scaled = await until(async: { await placeholder(in: controller) == "rgb(0, 0, 0)" })
        let seenPlaceholder = await placeholder(in: controller)
        #expect(scaled, "placeholder: \(seenPlaceholder)")

        controller.theme = ThemeAppearance(dayAccent: blue, nightAccent: red, darkBrightness: 1)
        let live = await until(async: { await colours(in: controller) == "rgb(255, 0, 0)|\(none)" })
        let seenLive = await colours(in: controller)
        #expect(live, "colours: \(seenLive)")
        let scaledLive = await until(async: { await placeholder(in: controller) == "rgb(53, 54, 59)" })
        let seenPlaceholderLive = await placeholder(in: controller)
        #expect(scaledLive, "placeholder: \(seenPlaceholderLive)")
        #expect(recorder.ready == [1])
        #expect(controller.webView.url == ReaderWebController.pageURL(token: 1))
    }

    /// #1213: « Doux » reaches the page's background, live, and « Blanc » takes it back off (today's white).
    @Test func theLightStyleSetsTheReaderBackgroundLiveAndBlancTakesItBack() async {
        let (controller, recorder) = makeController(transport: imageTransport())
        recorder.window?.overrideUserInterfaceStyle = .light
        var appearance = ThemeAppearance.standard
        appearance.lightStyle = .doux
        controller.theme = appearance
        controller.show(document(token: 5))
        #expect(await until { recorder.ready == [5] }, "ready: \(recorder.ready)")
        func background() async -> String {
            let script = "return getComputedStyle(document.body).backgroundColor;"
            return ((try? await evaluate(script, in: controller)) as? String) ?? ""
        }
        let soft = await until(async: { await background() == "rgb(245, 244, 239)" })
        let seenSoft = await background()
        #expect(soft, "doux: \(seenSoft)")
        controller.theme = .standard
        let white = await until(async: { await background() == "rgb(255, 255, 255)" })
        let seenWhite = await background()
        #expect(white, "blanc: \(seenWhite)")
        #expect(recorder.ready == [5])
    }

    @Test func theLightVariantGetsTheDayAccent() async {
        let (controller, recorder) = makeController(transport: imageTransport())
        recorder.window?.overrideUserInterfaceStyle = .light
        controller.theme = ThemeAppearance(dayAccent: red, nightAccent: blue, darkBrightness: 0)
        controller.show(document(token: 2))
        #expect(await until { recorder.ready == [2] }, "ready: \(recorder.ready)")
        // Light surfaces keep their light colour whatever the dark brightness.
        let light = await until(async: { await colours(in: controller) == "rgb(255, 0, 0)|\(none)" })
        let seen = await colours(in: controller)
        #expect(light, "colours: \(seen)")
    }

    /// LOT-122: the dark style reaches the page's background, live, and the standard style is the old colours.
    /// The `--app-dark-quote-background` value is still delivered but the default quote has no fill (#819).
    @Test func theDarkStyleSetsTheReaderBackgroundAndQuotesLive() async {
        let (controller, recorder) = makeController(transport: imageTransport())
        recorder.window?.overrideUserInterfaceStyle = .dark
        controller.show(document(token: 3))
        #expect(await until { recorder.ready == [3] }, "ready: \(recorder.ready)")
        func surfaces() async -> String {
            let script = """
                const root = getComputedStyle(document.documentElement);
                return getComputedStyle(document.body).backgroundColor + '|' + root.getPropertyValue('--app-dark-quote-background');
                """
            return ((try? await evaluate(script, in: controller)) as? String) ?? ""
        }
        let standard = await until(async: { await surfaces().hasPrefix("rgb(46, 47, 51)") })
        let seenStandard = await surfaces()
        #expect(standard, "standard: \(seenStandard)")

        var appearance = ThemeAppearance.standard
        appearance.darkStyle = .darker
        controller.theme = appearance
        let darker = await until(async: { await surfaces() == "rgb(11, 11, 12)|rgb(23, 24, 26)" })
        let seenDarker = await surfaces()
        #expect(darker, "darker: \(seenDarker)")
        let quote = await colours(in: controller)
        #expect(quote.hasSuffix("|\(none)"), "quote: \(quote)")
        // The layer behind the page (what shows while it bounces) follows: dark is the page's background, light the system's.
        func underPage() -> [Int] {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            controller.webView.underPageBackgroundColor?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return [red, green, blue].map { Int(($0 * 255).rounded()) }
        }
        #expect(await until { underPage() == [11, 11, 12] }, "under page, dark: \(underPage())")
        recorder.window?.overrideUserInterfaceStyle = .light
        #expect(await until { underPage() == [255, 255, 255] }, "under page, light: \(underPage())")
        recorder.window?.overrideUserInterfaceStyle = .dark

        appearance.darkStyle = .oled
        controller.theme = appearance
        let oled = await until(async: { await surfaces() == "rgb(0, 0, 0)|rgb(17, 17, 19)" })
        let seenOLED = await surfaces()
        #expect(oled, "oled: \(seenOLED)")
        #expect(recorder.ready == [3])
    }

    /// LOT-188: a gallery theme's tokens reach the page (its surface, links, quotes and code), live, and going back to Legacy
    /// gives the Legacy page again without a reload.
    @Test func aThemeRecoloursThePageAndLegacyRestoresIt() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        recorder.window?.overrideUserInterfaceStyle = .dark
        controller.show(document(token: 4))
        #expect(await until { recorder.ready == [4] }, "ready: \(recorder.ready)")
        func page() async -> String {
            let script = """
                const code = document.createElement('table'); code.className = 'code'; document.body.appendChild(code);
                const result = getComputedStyle(document.body).backgroundColor + '|' + getComputedStyle(code).backgroundColor;
                code.remove();
                return result;
                """
            return ((try? await evaluate(script, in: controller)) as? String) ?? ""
        }
        var themed = ThemeAppearance.standard
        let theme = try ThemeFixtures.testTheme()
        themed.themeVariants = theme.variants
        controller.theme = themed
        // Dark tokens: surface #1A2430, code #0A1018, link #8CC8FF, quote #222C38.
        let applied = await until(async: { await page() == "rgb(26, 36, 48)|rgb(10, 16, 24)" })
        let seenPage = await page()
        #expect(applied, "page: \(seenPage)")
        let linkAndQuote = await colours(in: controller)
        #expect(linkAndQuote == "rgb(140, 200, 255)|rgb(34, 44, 56)", "link and quote: \(linkAndQuote)")

        controller.theme = .standard
        let legacy = "\(ThemeAppearance.standard.nightAccent.cssRGB)|\(none)"
        let restored = await until(async: { await colours(in: controller) == legacy })
        let seenLegacy = await colours(in: controller)
        #expect(restored, "legacy: \(seenLegacy)")
        #expect(await page() == "rgb(0, 0, 0)|\(none)")
        #expect(recorder.ready == [4])
    }
}
