import Foundation
import HFRModels
@testable import SwiftHFR
import Testing
import UIKit

/// The contrast arithmetic of the reader's hosted tests: the background under a text is composited from its ancestors, as the
/// engine paints it, and a continuation's opacity fades text and surface toward the page.
enum ContrastProbe {
    static let helpers = """
    const rgba = (c) => {
        if (c === 'transparent') { return [0, 0, 0, 0]; }
        const m = c.match(/[\\d.]+/g).map(Number);
        return c.startsWith('color(') ? [...m.slice(0, 3).map((v) => v * 255), m.length > 3 ? m[3] : 1]
                                      : [m[0], m[1], m[2], m.length > 3 ? m[3] : 1];
    };
    const lum = (c) => {
        const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
        return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2]);
    };
    const under = (el) => {
        const layers = [];
        for (let e = el; e; e = e.parentElement) { layers.push(rgba(getComputedStyle(e).backgroundColor)); }
        let base = [255, 255, 255];
        for (const l of layers.reverse()) { base = base.map((v, i) => l[i] * l[3] + v * (1 - l[3])); }
        return base;
    };
    // A continuation's `opacity` fades the whole message (text and surfaces) toward the page white/black: composite both ends.
    const fade = (el, c) => {
        let o = 1;
        for (let e = el; e; e = e.parentElement) { o *= Number(getComputedStyle(e).opacity); }
        const bg = under(document.body);
        return c.slice(0, 3).map((v, i) => v * o + bg[i] * (1 - o));
    };
    const ratio = (el) => {
        const a = lum(fade(el, under(el))) + 0.05, b = lum(fade(el, rgba(getComputedStyle(el).color))) + 0.05;
        return Math.max(a, b) / Math.min(a, b);
    };
    """

    /// The contrast of the first element matching each selector, in order; -1 for a selector that matches nothing.
    static func script(selectors: [String]) -> String {
        let json = (try? JSONEncoder().encode(selectors)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return """
            \(helpers)
            return JSON.stringify(\(json).map((s) => { const e = document.querySelector(s); return e ? ratio(e) : -1; }));
            """
    }
}

/// What the earlier contrast suites did not vary (#1362): the header date of a classic message in light depends on the accent hue
/// the user picks (and on « Doux »), and the quotes nested in tinted quotes sit on the sum of their tints, on any message.
@MainActor
@Suite(.serialized)
struct ReaderContrastAccentAndNestingWebTests: ReaderWebTesting {
    private func page(token: Int, style: ThemeStyle, messages: [(author: String, html: String)]) -> ReaderDocument {
        let built = messages.enumerated().map { index, message in
            ReaderMessage(
                numreponse: index + 1, author: message.author, isDeleted: false, isContinuation: false, avatarURL: nil,
                dateText: "27-10-2026 10:01:00", editNote: nil, quotedByCount: nil, content: MessageContent(html: message.html)
            )
        }
        let readerPage = ReaderPage(topicID: readerTopic, title: "Titre", currentPage: 1, maxPage: 1, messages: built)
        let options = ReaderRenderOptions(style: style, visibility: VisibilityPolicy(ownPseudo: "moi", allowlist: ["ami"]))
        return ReaderDocument(
            token: token, html: TopicHTMLBuilder.document(for: readerPage, token: token, options: options),
            anchor: nil, keepsScrollPosition: false
        )
    }

    private func measure(
        _ selectors: [String], messages: [(author: String, html: String)], style: UIUserInterfaceStyle, look: ThemeStyle,
        appearance: ThemeAppearance, token: Int
    ) async -> [Double]? {
        let (controller, recorder) = makeController(transport: imageTransport())
        recorder.window?.overrideUserInterfaceStyle = style
        controller.theme = appearance
        controller.show(page(token: token, style: look, messages: messages))
        let script = ContrastProbe.script(selectors: selectors)
        guard await until({ recorder.ready == [token] }) else { return nil }
        var seen: [Double]?
        _ = await until(async: {
            let json = (try? await self.evaluate(script, in: controller)) as? String ?? ""
            seen = try? JSONDecoder().decode([Double].self, from: Data(json.utf8))
            return seen != nil
        })
        return seen
    }

    private static func appearance(hue degrees: Double, lightStyle: LightStyle = .blanc) -> ThemeAppearance {
        let hue = degrees / 360
        return ThemeAppearance(
            dayAccent: ThemeAppearance.dayTint(hue: hue), nightAccent: ThemeAppearance.nightTint(hue: hue),
            darkBrightness: ThemeAppearance.defaultDarkBrightness, lightStyle: lightStyle
        )
    }

    /// The header date of a plain message and of one of mine, classic look, light: `--secondary` on 15 % of the accent.
    @Test(arguments: [0.0, 30, 60, 90, 120, 150, 180, 190, 210, 240, 270, 300, 330])
    func classicLightHeaderDateHoldsAAAtEveryHue(hue: Double) async {
        let selectors = ["article.message:not(.me) .header .date", "article.message.me .header .date"]
        let messages = [(author: "inconnu", html: "<p>texte</p>"), (author: "moi", html: "<p>texte</p>")]
        for lightStyle in [LightStyle.blanc, .doux] {
            let seen = await measure(
                selectors, messages: messages, style: .light, look: .classic,
                appearance: Self.appearance(hue: hue, lightStyle: lightStyle), token: Int(hue) + 1
            )
            guard let seen else { Issue.record("the reader did not answer"); return }
            #expect(seen[0] >= 4.5, "plain header date, hue \(hue), style \(lightStyle): \(seen[0])")
            #expect(seen[1] >= 4.5, "own header date, hue \(hue), style \(lightStyle): \(seen[1])")
        }
    }

    private static func quote(_ kind: String, probe: String, inner: String = "") -> String {
        """
        <table class="citation \(kind)"><tr class="none"><td><b class="s1" data-probe="\(probe)">x a écrit :</b><br>\
        <p>cité</p>\(inner)</td></tr></table>
        """
    }

    /// Quotes nested in tinted quotes: the inner header sits on the sum of the tints (5 % text twice, a 3 % accent, 30 % love).
    private static let nested = [
        quote("quote-blocked open", probe: "o1", inner: quote("quote-blocked open", probe: "bb")),
        quote("quote-me", probe: "o2", inner: quote("quote-blocked open", probe: "mb")),
        quote("quote-allowed", probe: "o3", inner: quote("quote-blocked open", probe: "ab")),
        quote("quote-blocked open", probe: "o4", inner: quote("quote-me", probe: "bm")),
        quote("quote-blocked open", probe: "o5", inner: quote("quote-allowed", probe: "ba")),
        quote(
            "quote-blocked open", probe: "o6",
            inner: quote("quote-blocked open", probe: "b3", inner: quote("quote-blocked open", probe: "bbb"))
        )
    ].joined()

    enum Author: String, CaseIterable, Sendable {
        case plain = "inconnu", allowlisted = "ami", moderation = "Modération", own = "moi"
    }

    @Test(arguments: Author.allCases)
    func nestedQuoteHeadersHoldAA(author: Author) async {
        let probes = ["bb", "mb", "ab", "bm", "ba", "b3", "bbb"]
        var token = 1000
        for look in [ThemeStyle.modern, .classic] {
            for style in [UIUserInterfaceStyle.light, .dark] {
                for hue in [190.0, 60.0] {
                    token += 1
                    let seen = await measure(
                        probes.map { "[data-probe=\"\($0)\"]" }, messages: [(author: author.rawValue, html: Self.nested)],
                        style: style, look: look, appearance: Self.appearance(hue: hue), token: token
                    )
                    guard let seen else { Issue.record("the reader did not answer"); return }
                    for (probe, ratio) in zip(probes, seen) {
                        #expect(ratio >= 4.5, "nested header \(probe), \(author), \(look), \(style.rawValue), hue \(hue): \(ratio)")
                    }
                }
            }
        }
    }
}
