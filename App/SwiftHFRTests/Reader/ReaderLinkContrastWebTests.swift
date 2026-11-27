import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing
import UIKit

/// A body link holds WCAG AA (4.5:1) in the real reader at every accent hue (#1374): `--action`, the accent, was 1.5:1 on white at
/// the default hue, so links take `ThemeAppearance.linkColor`. Every surface a link can sit on is measured: the page, a quote, a
/// quote nested in tinted quotes, a spoiler, a code block and the allowlisted, moderation and own messages, on a continuation too.
@MainActor
@Suite(.serialized)
struct ReaderLinkContrastWebTests: ReaderWebTesting {
    /// How the reader is drawn for one measure: the system appearance, the message look, the light and dark styles and the hue.
    struct Run: Sendable {
        var hue: Double
        var look: ThemeStyle
        var style: UIUserInterfaceStyle
        var lightStyle: LightStyle
        var darkStyle: DarkStyle
        var isContinuation = false
    }

    private static let authors = ["inconnu", "ami", "Modération", "moi"]

    private static func link(_ probe: String) -> String { "<a href=\"https://example.com/x\" data-probe=\"\(probe)\">lien</a>" }

    private static func quote(_ kind: String, probe: String, inner: String = "") -> String {
        """
        <table class="citation \(kind)"><tr class="none"><td><b class="s1">x a écrit :</b><br>\
        <p>cité \(link(probe))</p>\(inner)</td></tr></table>
        """
    }

    /// One message body per author: a link on the page and in every kind of quote, nested ones, a spoiler and a code block.
    private static func body(_ index: Int) -> String {
        let nested = quote("quote-blocked open", probe: "\(index)-n1", inner: quote("quote-blocked open", probe: "\(index)-n2"))
        return """
            <p>texte \(link("\(index)-page"))</p>\(quote("", probe: "\(index)-quote"))\(quote("quote-me", probe: "\(index)-me"))\
            \(quote("quote-allowed", probe: "\(index)-allowed"))\(nested)\
            <table class="spoiler"><tr class="none"><td><div class="masque">\(link("\(index)-spoiler"))</div></td></tr></table>\
            <table class="code"><tr class="none"><td><b class="s1">Code :</b><br><ol class="olcode">\
            <li><span style="color:blue" data-probe="\(index)-code">x</span></li></ol></td></tr></table>
            """
    }

    private static let kinds = ["page", "quote", "me", "allowed", "n1", "n2", "spoiler", "code"]
    private static var probes: [String] { authors.indices.flatMap { index in kinds.map { "\(index)-\($0)" } } }

    private func document(_ run: Run, token: Int) -> ReaderDocument {
        let messages = Self.authors.enumerated().map { index, author in
            ReaderMessage(
                numreponse: index + 1, author: author, isDeleted: false, isContinuation: run.isContinuation, avatarURL: nil,
                dateText: "27-10-2026 10:01:00", editNote: nil, quotedByCount: nil, content: MessageContent(html: Self.body(index))
            )
        }
        let page = ReaderPage(topicID: readerTopic, title: "Titre", currentPage: 1, maxPage: 1, messages: messages)
        let options = ReaderRenderOptions(style: run.look, visibility: VisibilityPolicy(ownPseudo: "moi", allowlist: ["ami"]))
        return ReaderDocument(
            token: token, html: TopicHTMLBuilder.document(for: page, token: token, options: options),
            anchor: nil, keepsScrollPosition: false
        )
    }

    private func appearance(_ run: Run) -> ThemeAppearance {
        let hue = run.hue / 360
        return ThemeAppearance(
            dayAccent: ThemeAppearance.dayTint(hue: hue), nightAccent: ThemeAppearance.nightTint(hue: hue),
            darkBrightness: ThemeAppearance.maximumDarkBrightness, darkStyle: run.darkStyle, lightStyle: run.lightStyle
        )
    }

    private func measure(_ run: Run, token: Int) async -> [Double]? {
        let (controller, recorder) = makeController(transport: imageTransport())
        recorder.window?.overrideUserInterfaceStyle = run.style
        controller.theme = appearance(run)
        controller.show(document(run, token: token))
        let script = ContrastProbe.script(selectors: Self.probes.map { "[data-probe=\"\($0)\"]" })
        guard await until({ recorder.ready == [token] }) else { return nil }
        var seen: [Double]?
        _ = await until(async: {
            let json = (try? await self.evaluate(script, in: controller)) as? String ?? ""
            seen = try? JSONDecoder().decode([Double].self, from: Data(json.utf8))
            return seen != nil
        })
        return seen
    }

    private func check(_ run: Run, token: Int) async {
        guard let seen = await measure(run, token: token) else { Issue.record("the reader did not answer"); return }
        let setting = "\(run.look), \(run.style.rawValue), \(run.lightStyle), \(run.darkStyle), continuation \(run.isContinuation)"
        for (probe, ratio) in zip(Self.probes, seen) {
            #expect(ratio >= 4.5, "link \(probe), hue \(run.hue), \(setting): \(ratio)")
        }
    }

    /// Every hue of the slider, both looks, « Blanc » and « Doux » in light, the three dark styles (at 150 % brightness) in dark.
    @Test(arguments: [0.0, 30, 60, 90, 120, 150, 180, 190, 210, 240, 270, 300, 330])
    func linksHoldAAAtEveryHue(hue: Double) async {
        var token = Int(hue) * 100
        for look in [ThemeStyle.modern, .classic] {
            for lightStyle in [LightStyle.blanc, .doux] {
                token += 1
                await check(Run(hue: hue, look: look, style: .light, lightStyle: lightStyle, darkStyle: .standard), token: token)
            }
            for darkStyle in DarkStyle.allCases {
                token += 1
                await check(Run(hue: hue, look: look, style: .dark, lightStyle: .blanc, darkStyle: darkStyle), token: token)
            }
        }
    }

    /// A continuation fades its whole message (75 % opacity) toward the page.
    @Test(arguments: [190.0, 60, 240])
    func continuationLinksHoldAA(hue: Double) async {
        var token = 90_000 + Int(hue) * 10
        for style in [UIUserInterfaceStyle.light, .dark] {
            token += 1
            let run = Run(hue: hue, look: .classic, style: style, lightStyle: .blanc, darkStyle: .standard, isContinuation: true)
            await check(run, token: token)
        }
    }

    /// A body link is the accent moved toward text, so it stays recognisable: the same hue within a few degrees.
    @Test(arguments: [0.0, 60, 120, 190, 240, 300])
    func linkColourKeepsTheAccentHue(hue: Double) {
        let appearance = ThemeAppearance(
            dayAccent: ThemeAppearance.dayTint(hue: hue / 360), nightAccent: ThemeAppearance.nightTint(hue: hue / 360),
            darkBrightness: 1
        )
        for dark in [false, true] {
            let link = appearance.linkColor(dark: dark)
            let degrees = link.hsb.hue * 360
            let difference = abs(degrees - hue)
            #expect(min(difference, 360 - difference) < 6, "hue \(hue), dark \(dark): link hue \(degrees)")
        }
    }

    /// An accent that already reads is left alone; the fills keep the accent.
    @Test func readableAccentIsKept() {
        let appearance = ThemeAppearance(
            dayAccent: ThemeColor(hex: 0x0B1F66), nightAccent: ThemeColor(hex: 0xE6F0FF), darkBrightness: 1
        )
        #expect(appearance.linkColor(dark: false) == appearance.dayAccent)
        #expect(appearance.linkColor(dark: true) == appearance.nightAccent)
    }

    /// Legacy sends the link colours; a gallery theme sends none: its own `link` token paints its links.
    @Test func onlyLegacySendsTheLinkVariables() throws {
        let legacy = ThemeAppearance.standard
        #expect(legacy.readerLinkVariables.map(\.name) == ["--app-link-light", "--app-link-dark"])
        #expect(legacy.readerVariables.contains { $0.name == "--app-link-light" })
        let catalog = try ThemeFixtures.catalog()
        let model = ThemeSettingsModel(store: InMemorySettingsStore(), catalog: catalog)
        model.select(try #require(catalog.themes.first { $0.id == "test-theme" }))
        #expect(model.appearance.readerLinkVariables.isEmpty)
        #expect(!model.appearance.readerVariables.contains { $0.name.hasPrefix("--app-link") })
    }
}
