import Foundation
import HFRModels
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

    /// Rounded channels of: article 1 and 2 backgrounds, article 1's bottom rule, the quiet `--separator` (as a border colour, since the
    /// app supplies it as rgb()), the quote's background; then the rule's width.
    private let probe = """
        // color-mix() computes to color(srgb 0.95 …) in some engines and rgb() in others: both become rounded 0-255 channels.
        const channels = (c) => {
            const m = c.match(/[\\d.]+/g).map(Number);
            return c.startsWith('color(') ? m.slice(0, 3).map((v) => Math.round(v * 255)) : m;
        };
        const articles = document.querySelectorAll('article.message');
        const first = getComputedStyle(articles[0]), second = getComputedStyle(articles[1]);
        const quote = getComputedStyle(articles[1].querySelector('table.quote'));
        const quiet = document.createElement('div');
        quiet.style.cssText = 'border-top: 1px solid var(--separator)';
        document.body.appendChild(quiet);
        const separator = getComputedStyle(quiet).borderTopColor;
        quiet.remove();
        return JSON.stringify([channels(first.backgroundColor), channels(second.backgroundColor), channels(first.borderBottomColor),
                               channels(separator), channels(quote.backgroundColor), [parseFloat(first.borderBottomWidth)]]);
        """

    /// RGB channels may differ by 1 (engines round a colour mix differently); alpha and the border width must be exact, so a
    /// 0 px rule cannot pass for a 1 px one.
    private func matches(_ seen: String?, _ expected: [[Double]]) -> Bool {
        guard let data = seen?.data(using: .utf8), let values = try? JSONDecoder().decode([[Double]].self, from: data),
              values.count == expected.count else { return false }
        return zip(values, expected).enumerated().allSatisfy { index, pair in
            let (got, want) = pair
            let isWidth = index == expected.count - 1
            return got.count == want.count && zip(got, want).enumerated().allSatisfy { channel, values in
                abs(values.0 - values.1) <= (isWidth || channel == 3 ? 0 : 1)
            }
        }
    }

    private func read(style: UIUserInterfaceStyle, token: Int, expected: [[Double]]) async -> (Bool, String) {
        let (controller, recorder) = makeController(transport: imageTransport())
        recorder.window?.overrideUserInterfaceStyle = style
        controller.show(twoMessages(token: token))
        guard await until({ recorder.ready == [token] }) else { return (false, "not ready: \(recorder.ready)") }
        let matched = await until(async: { self.matches(try? await self.evaluate(self.probe, in: controller) as? String, expected) })
        return (matched, ((try? await evaluate(probe, in: controller)) as? String) ?? "")
    }

    // 0x1C1C1E at 5 % over white: 244; rule at 25 %: 198,198,199 (the quiet separator is #d1d1d6: lighter); quote on --placeholder #e5e5ea.
    @Test func inLightTheSecondMessageIsTintedAndTheRuleIsStrongerThanTheQuietSeparator() async {
        let (matched, seen) = await read(
            style: .light, token: 1,
            expected: [[0, 0, 0, 0], [244, 244, 244], [198, 198, 199], [209, 209, 214], [229, 229, 234], [1]]
        )
        #expect(matched, "seen: \(seen)")
    }

    // 0xF2F2F7 at 9 % over black: 22; rule at 35 %: 85,85,86, against the app's quiet separator rgb(56, 56, 58); quote on #2c2c2e.
    @Test func inDarkTheSecondMessageIsTintedAndTheRuleIsStrongerThanTheQuietSeparator() async {
        let (matched, seen) = await read(
            style: .dark, token: 2,
            expected: [[0, 0, 0, 0], [22, 22, 22], [85, 85, 86], [56, 56, 58], [44, 44, 46], [1]]
        )
        #expect(matched, "seen: \(seen)")
    }
}
