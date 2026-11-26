import Foundation
import HFRModels
@testable import SwiftHFR
import Testing
import UIKit

/// Secondary text on the tinted whitelist surfaces keeps WCAG AA (4.5:1) in the real reader (#644): the classic whitelist header's
/// date (`--love`) and the folded blocked quote header inside a whitelisted author's message (a tint over `--love`), modern and
/// classic, light and dark. The background under the text is composited from the element's ancestors, as the engine paints it.
@MainActor
@Suite(.serialized)
struct ReaderWhitelistContrastWebTests: ReaderWebTesting {
    private func document(token: Int, style: ThemeStyle) -> ReaderDocument {
        let html = """
            <p>texte</p><table class="citation quote-blocked"><tr class="none"><td><b class="s1">Citation masquée</b><br>\
            <p>cité</p></td></tr></table>
            """
        let message = ReaderMessage(
            numreponse: 1, author: "ami", isDeleted: false, isContinuation: false, avatarURL: nil,
            dateText: "27-10-2026 10:01:00", editNote: nil, quotedByCount: nil, content: MessageContent(html: html)
        )
        let page = ReaderPage(topicID: readerTopic, title: "Titre", currentPage: 1, maxPage: 1, messages: [message])
        let options = ReaderRenderOptions(style: style, visibility: VisibilityPolicy(allowlist: ["ami"]))
        return ReaderDocument(
            token: token, html: TopicHTMLBuilder.document(for: page, token: token, options: options), anchor: nil, keepsScrollPosition: false
        )
    }

    /// [header date contrast, blocked quote header contrast] of the first message.
    private let probe = """
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
        const ratio = (el) => {
            const a = lum(under(el)) + 0.05, b = lum(rgba(getComputedStyle(el).color)) + 0.05;
            return Math.max(a, b) / Math.min(a, b);
        };
        const root = document.querySelector('article.message.whitelist');
        if (!root) { return 'null'; }
        return JSON.stringify([ratio(root.querySelector('.header .date')), ratio(root.querySelector('table.quote-blocked b.s1'))]);
        """

    private func read(style: UIUserInterfaceStyle, theme: ThemeStyle, token: Int) async -> [Double]? {
        let (controller, recorder) = makeController(transport: imageTransport())
        recorder.window?.overrideUserInterfaceStyle = style
        controller.show(document(token: token, style: theme))
        guard await until({ recorder.ready == [token] }) else { return nil }
        var seen: [Double]?
        _ = await until(async: {
            let json = (try? await self.evaluate(self.probe, in: controller)) as? String ?? ""
            seen = try? JSONDecoder().decode([Double].self, from: Data(json.utf8))
            return seen != nil
        })
        return seen
    }

    private func check(style: UIUserInterfaceStyle, theme: ThemeStyle, token: Int) async {
        guard let seen = await read(style: style, theme: theme, token: token) else {
            Issue.record("the reader did not answer")
            return
        }
        #expect(seen[0] >= 4.5, "whitelist header date: \(seen[0])")
        #expect(seen[1] >= 4.5, "blocked quote header in a whitelisted message: \(seen[1])")
    }

    @Test func inModernLightSecondaryTextHoldsAA() async { await check(style: .light, theme: .modern, token: 1) }
    @Test func inModernDarkSecondaryTextHoldsAA() async { await check(style: .dark, theme: .modern, token: 2) }
    @Test func inClassicLightSecondaryTextHoldsAA() async { await check(style: .light, theme: .classic, token: 3) }
    @Test func inClassicDarkSecondaryTextHoldsAA() async { await check(style: .dark, theme: .classic, token: 4) }
}
