import Foundation
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

    private func colours(in controller: ReaderWebController) async -> String {
        ((try? await evaluate(probe, in: controller)) as? String) ?? ""
    }

    private let red = ThemeColor(red: 1, green: 0, blue: 0)
    private let blue = ThemeColor(red: 0, green: 0, blue: 1)

    @Test func theDarkVariantGetsTheNightAccentAndTheScaledSurfacesThenFollowsAChangeLive() async {
        let (controller, recorder) = makeController(transport: imageTransport())
        recorder.window?.overrideUserInterfaceStyle = .dark
        controller.theme = ThemeAppearance(dayAccent: red, nightAccent: blue, darkBrightness: 1.5)
        controller.show(document(token: 1))
        #expect(await until { recorder.ready == [1] }, "ready: \(recorder.ready)")
        // 0x1C1C1E at 150 %: rgb(42, 42, 45) (ThemeAppearanceTests).
        let expected = "rgb(0, 0, 255)|rgb(42, 42, 45)"
        let first = await until(async: { await colours(in: controller) == expected })
        let seen = await colours(in: controller)
        #expect(first, "colours: \(seen)")

        controller.theme = ThemeAppearance(dayAccent: blue, nightAccent: red, darkBrightness: 1)
        let live = await until(async: { await colours(in: controller) == "rgb(255, 0, 0)|rgb(28, 28, 30)" })
        let seenLive = await colours(in: controller)
        #expect(live, "colours: \(seenLive)")
        #expect(recorder.ready == [1])
        #expect(controller.webView.url == ReaderWebController.pageURL(token: 1))
    }

    @Test func theLightVariantGetsTheDayAccent() async {
        let (controller, recorder) = makeController(transport: imageTransport())
        recorder.window?.overrideUserInterfaceStyle = .light
        controller.theme = ThemeAppearance(dayAccent: red, nightAccent: blue, darkBrightness: 0)
        controller.show(document(token: 2))
        #expect(await until { recorder.ready == [2] }, "ready: \(recorder.ready)")
        // Light quotes keep their light colour whatever the dark brightness.
        let light = await until(async: { await colours(in: controller) == "rgb(255, 0, 0)|rgb(242, 242, 247)" })
        let seen = await colours(in: controller)
        #expect(light, "colours: \(seen)")
    }

    /// LOT-122: the dark style reaches the page's background and quote surfaces, live, and the standard style is the old colours.
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
        let standard = await until(async: { await surfaces().hasPrefix("rgb(0, 0, 0)") })
        let seenStandard = await surfaces()
        #expect(standard, "standard: \(seenStandard)")

        var appearance = ThemeAppearance.standard
        appearance.darkStyle = .darker
        controller.theme = appearance
        let darker = await until(async: { await surfaces() == "rgb(11, 11, 12)|rgb(23, 24, 26)" })
        let seenDarker = await surfaces()
        #expect(darker, "darker: \(seenDarker)")
        let quote = await colours(in: controller)
        #expect(quote.hasSuffix("|rgb(23, 24, 26)"), "quote: \(quote)")
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
}
