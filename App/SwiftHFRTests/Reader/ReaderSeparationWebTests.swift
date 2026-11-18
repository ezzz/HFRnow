import Foundation
import HFRModels
@testable import SwiftHFR
import Testing
import UIKit

/// Message separation in the real reader: no message has a background of its own, so neighbours never differ (#1210 removed the
/// alternating tint of #568; legacy's dark CSS has none), and the rule below a message is still stronger than the quiet separator,
/// in light and in dark, modern and classic.
@MainActor
@Suite(.serialized)
struct ReaderSeparationWebTests: ReaderWebTesting {
    private func twoMessages(token: Int, style: ThemeStyle) -> ReaderDocument {
        func message(_ number: Int, _ text: String) -> ReaderMessage {
            ReaderMessage(
                numreponse: number, author: "auteur", isDeleted: false, isContinuation: false, avatarURL: nil,
                dateText: "27-10-2026 10:0\(number):00", editNote: nil, quotedByCount: nil, content: MessageContent(html: "<p>\(text)</p>")
            )
        }
        let messages = [message(1, "un"), message(2, "deux"), message(3, "trois")]
        let page = ReaderPage(topicID: readerTopic, title: "Titre", currentPage: 1, maxPage: 1, messages: messages)
        let html = TopicHTMLBuilder.document(for: page, token: token, options: ReaderRenderOptions(style: style))
        return ReaderDocument(token: token, html: html, anchor: nil, keepsScrollPosition: false)
    }

    /// [alpha of each article's background (three of them), the first article's bottom rule width, its colour channels, the quiet
    ///  `--separator` as a border colour (the app supplies it as rgb()), whether `--surface-alt` is still defined (1) or not (0),
    ///  whether the first message's date is drawn in the page text colour (1) or not (0)].
    private let probe = """
        // color-mix() computes to color(srgb 0.95 …) in some engines and rgb() in others: both become rounded 0-255 channels.
        const channels = (c) => {
            const m = c.match(/[\\d.]+/g).map(Number);
            return c.startsWith('color(') ? m.slice(0, 3).map((v) => Math.round(v * 255)) : m.slice(0, 3);
        };
        const alpha = (c) => {
            if (c === 'transparent') { return 0; }
            const m = c.match(/[\\d.]+/g).map(Number);
            return m.length > 3 ? m[3] : 1;
        };
        const articles = [...document.querySelectorAll('article.message')];
        const first = getComputedStyle(articles[0]);
        const quiet = document.createElement('div');
        quiet.style.cssText = 'border-top: 1px solid var(--separator)';
        document.body.appendChild(quiet);
        const separator = getComputedStyle(quiet).borderTopColor;
        quiet.remove();
        const alt = getComputedStyle(document.documentElement).getPropertyValue('--surface-alt').trim();
        const textProbe = document.createElement('i');
        textProbe.style.color = 'var(--text)';
        document.body.appendChild(textProbe);
        const dateIsText = getComputedStyle(articles[0].querySelector('.date')).color === getComputedStyle(textProbe).color;
        textProbe.remove();
        return JSON.stringify([articles.map((a) => alpha(getComputedStyle(a).backgroundColor)),
                               parseFloat(first.borderBottomWidth), channels(first.borderBottomColor), channels(separator),
                               alt === '' ? 0 : 1, dateIsText ? 1 : 0]);
        """

    private struct Seen: Decodable {
        let alphas: [Double]
        let width: Double
        let rule: [Double]
        let quiet: [Double]
        let altDefined: Double
        let dateIsText: Double

        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            alphas = try container.decode([Double].self)
            width = try container.decode(Double.self)
            rule = try container.decode([Double].self)
            quiet = try container.decode([Double].self)
            altDefined = try container.decode(Double.self)
            dateIsText = try container.decode(Double.self)
        }
    }

    private func read(style: UIUserInterfaceStyle, theme: ThemeStyle, token: Int) async -> Seen? {
        let (controller, recorder) = makeController(transport: imageTransport())
        recorder.window?.overrideUserInterfaceStyle = style
        controller.show(twoMessages(token: token, style: theme))
        guard await until({ recorder.ready == [token] }) else { return nil }
        var seen: Seen?
        _ = await until(async: {
            let json = (try? await self.evaluate(self.probe, in: controller)) as? String ?? ""
            seen = try? JSONDecoder().decode(Seen.self, from: Data(json.utf8))
            return seen != nil
        })
        return seen
    }

    private func check(style: UIUserInterfaceStyle, theme: ThemeStyle, token: Int, rule: [Double], quiet: [Double]) async {
        guard let seen = await read(style: style, theme: theme, token: token) else {
            Issue.record("the reader did not answer")
            return
        }
        #expect(seen.alphas == [0, 0, 0], "no message has a background of its own: \(seen.alphas)")
        #expect(seen.altDefined == 0, "--surface-alt no longer exists")
        #expect(seen.width == 1, "the message rule is still there: \(seen.width)")
        // RGB channels may differ by 1 (engines round a colour mix differently).
        #expect(zip(seen.rule, rule).allSatisfy { abs($0 - $1) <= 1 }, "rule: \(seen.rule)")
        #expect(zip(seen.quiet, quiet).allSatisfy { abs($0 - $1) <= 1 }, "quiet separator: \(seen.quiet)")
        #expect(seen.rule != seen.quiet, "the message rule is stronger than the quiet separator")
    }

    // Rule at 25 % of 0x1C1C1E over white: 198,198,199, against the quiet separator #d1d1d6.
    @Test func inLightNoMessageHasATintAndTheRuleIsStrongerThanTheQuietSeparator() async {
        await check(style: .light, theme: .modern, token: 1, rule: [198, 198, 199], quiet: [209, 209, 214])
    }

    // Rule at 35 % of 0xF2F2F7 over the legacy grey #2E2F33 (#1210): the page is no longer black, so the rule is lighter than the
    // 85,85,86 of the black page; the quiet separator is the standard style's `--app-dark-separator` when the app sets it, else
    // the CSS fallback #4a4b50. Only the relations are pinned here, the exact values belong to `ThemeAppearanceTests`.
    @Test func inDarkNoMessageHasATintAndTheRuleIsStrongerThanTheQuietSeparator() async {
        guard let seen = await read(style: .dark, theme: .modern, token: 2) else {
            Issue.record("the reader did not answer")
            return
        }
        #expect(seen.alphas == [0, 0, 0], "no message has a background of its own: \(seen.alphas)")
        #expect(seen.altDefined == 0, "--surface-alt no longer exists")
        #expect(seen.width == 1, "the message rule is still there: \(seen.width)")
        #expect(seen.rule != seen.quiet)
        #expect(zip(seen.rule, seen.quiet).allSatisfy { $0 > $1 }, "the rule is lighter than the separator: \(seen.rule) / \(seen.quiet)")
    }

    @Test func inClassicLightNoMessageHasATint() async {
        await check(style: .light, theme: .classic, token: 3, rule: [198, 198, 199], quiet: [209, 209, 214])
    }

    @Test func inClassicDarkNoMessageHasATint() async {
        guard let seen = await read(style: .dark, theme: .classic, token: 4) else {
            Issue.record("the reader did not answer")
            return
        }
        #expect(seen.alphas == [0, 0, 0], "no message has a background of its own: \(seen.alphas)")
        #expect(seen.width == 1)
        // The classic header is 15 % accent over the page; secondary text on it was 3.75:1 over the legacy grey.
        #expect(seen.dateIsText == 1, "the classic header's date is drawn in the page text colour in dark")
    }
}
