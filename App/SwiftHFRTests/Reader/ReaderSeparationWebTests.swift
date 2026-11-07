import Foundation
@testable import SwiftHFR
import Testing
import UIKit

/// Message separation in the real reader (#568): the even message sits on a tint of the text colour, the rule below a message is
/// stronger than the quiet separator, in light and in dark, and a quote inside a tinted message keeps its own surface.
@MainActor
@Suite(.serialized)
struct ReaderSeparationWebTests: ReaderWebTesting {
    /// Two messages, the second quoting someone, so the quote sits on an even (tinted) article.
    private func twoMessages(token: Int) -> ReaderDocument {
        let plain = ReaderMessage(
            numreponse: 1, author: "auteur", isDeleted: false, isContinuation: false, avatarURL: nil,
            dateText: "27-10-2026 10:00:00", editNote: nil, quotedByCount: nil, content: MessageContent(html: "<p>un</p>")
        )
        let quoted = ReaderMessage(
            numreponse: 2, author: "autre", isDeleted: false, isContinuation: false, avatarURL: nil,
            dateText: "27-10-2026 10:01:00", editNote: nil, quotedByCount: nil,
            content: MessageContent(html: "<table class=\"quote\"><tr><td><p>cité</p></td></tr></table><p>deux</p>")
        )
        let page = ReaderPage(topicID: readerTopic, title: "Titre", currentPage: 1, maxPage: 1, messages: [plain, quoted])
        return ReaderDocument(
            token: token, html: TopicHTMLBuilder.document(for: page, token: token), anchor: nil, keepsScrollPosition: false
        )
    }

    /// Background of articles 1 and 2, the colour and width of article 1's bottom rule, the quiet separator, the quote's background.
    private let probe = """
        // color-mix() computes to color(srgb 0.95 …) in some engines and rgb() in others: both become rounded 0-255 channels.
        const channels = (c) => {
            const m = c.match(/[\\d.]+/g).map(Number);
            return (c.startsWith('color(') ? m.slice(0, 3).map((v) => Math.round(v * 255)) : m).join(',');
        };
        const articles = document.querySelectorAll('article.message');
        const first = getComputedStyle(articles[0]), second = getComputedStyle(articles[1]);
        const quote = getComputedStyle(articles[1].querySelector('table.quote'));
        return [channels(first.backgroundColor), channels(second.backgroundColor), channels(first.borderBottomColor),
                first.borderBottomWidth, getComputedStyle(document.documentElement).getPropertyValue('--separator').trim(),
                channels(quote.backgroundColor)].join('|');
        """

    private func read(style: UIUserInterfaceStyle, token: Int, expected: String) async -> (Bool, String) {
        let (controller, recorder) = makeController(transport: imageTransport())
        recorder.window?.overrideUserInterfaceStyle = style
        controller.show(twoMessages(token: token))
        guard await until({ recorder.ready == [token] }) else { return (false, "not ready: \(recorder.ready)") }
        let matched = await until(async: { ((try? await self.evaluate(self.probe, in: controller)) as? String) == expected })
        return (matched, ((try? await evaluate(probe, in: controller)) as? String) ?? "")
    }

    // 0x1C1C1E text at 5 % over white: 244,244,244; rule #c6c6c8; quote on --placeholder #e5e5ea.
    @Test func inLightTheSecondMessageIsTintedAndTheRuleIsStrongerThanTheQuietSeparator() async {
        let (matched, seen) = await read(
            style: .light, token: 1,
            expected: "0,0,0,0|244,244,244|198,198,200|1px|#d1d1d6|229,229,234"
        )
        #expect(matched, "seen: \(seen)")
    }

    // 0xF2F2F7 text at 9 % over black: 22,22,22; rule #545458; quote on --placeholder #2c2c2e.
    @Test func inDarkTheSecondMessageIsTintedAndTheRuleIsStrongerThanTheQuietSeparator() async {
        let (matched, seen) = await read(
            style: .dark, token: 2,
            expected: "0,0,0,0|22,22,22|84,84,88|1px|#38383a|44,44,46"
        )
        #expect(matched, "seen: \(seen)")
    }
}
