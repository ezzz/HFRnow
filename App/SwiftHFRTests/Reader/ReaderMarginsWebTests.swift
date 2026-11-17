import Foundation
import HFRModels
@testable import SwiftHFR
import Testing
import UIKit

/// #1038 in the real reader: the signature text sits at the message text's left inset while its dotted rule starts at the
/// message edge, the text has legacy's right padding (`div[id^=para] { padding-right: 10px }`, `style-liste-light.css:505-509`,
/// `style-liste-dark.css:506-509`, `style-liste-oled.css:502-505` @ 87fe0d1c), and no rule frames a quote (legacy:
/// `border: none; border-left`, `style-liste-dark.css:296-300`).
@MainActor
@Suite(.serialized)
struct ReaderMarginsWebTests: ReaderWebTesting {
    private func document(token: Int, style: ThemeStyle) -> ReaderDocument {
        let message = ReaderMessage(
            numreponse: 1, author: "auteur", isDeleted: false, isContinuation: false, avatarURL: nil,
            dateText: "27-10-2026 10:00:00", editNote: nil, quotedByCount: nil,
            content: MessageContent(
                html: """
                    <div class="container"><table class="citation"><tr class="none">
                    <td><b class="s1">cite :</b><p>cité</p></td></tr></table></div>
                    <p>un texte assez long pour passer à la ligne dans la fenêtre de test, et vérifier la marge de droite du texte</p>
                    """,
                signatureHTML: "<br />ma signature"
            )
        )
        let page = ReaderPage(topicID: readerTopic, title: "Titre", currentPage: 1, maxPage: 1, messages: [message])
        let options = ReaderRenderOptions(style: style, showsSignatures: true)
        return ReaderDocument(
            token: token, html: TopicHTMLBuilder.document(for: page, token: token, options: options), anchor: nil,
            keepsScrollPosition: false
        )
    }

    /// [signature text left minus message text left, signature rule left minus article left, content padding-right,
    ///  signature right padding minus content right padding, quote and container and cell top/bottom border widths (sum),
    ///  signature rule right minus article right].
    private let probe = """
        const article = document.querySelector('article.message').getBoundingClientRect();
        const content = document.querySelector('.content'), cs = getComputedStyle(content);
        const textLeft = content.getBoundingClientRect().left + parseFloat(cs.paddingLeft) + parseFloat(cs.borderLeftWidth);
        const sig = document.querySelector('.signature'), ss = getComputedStyle(sig), box = sig.getBoundingClientRect();
        const sigLeft = box.left + parseFloat(ss.borderLeftWidth) + parseFloat(ss.paddingLeft);
        const widths = (el) => { const s = getComputedStyle(el); return parseFloat(s.borderTopWidth) + parseFloat(s.borderBottomWidth); };
        const framing = widths(document.querySelector('div.container')) + widths(document.querySelector('table.citation'))
            + widths(document.querySelector('table.citation tr')) + widths(document.querySelector('table.citation td'));
        return JSON.stringify([sigLeft - textLeft, box.left - article.left, parseFloat(cs.paddingRight),
                               parseFloat(ss.paddingRight) - parseFloat(cs.paddingRight), framing, box.right - article.right]);
        """

    private func measure(style: ThemeStyle, dark: Bool, token: Int) async -> [Double] {
        let (controller, recorder) = makeController(transport: imageTransport())
        recorder.window?.overrideUserInterfaceStyle = dark ? .dark : .light
        controller.show(document(token: token, style: style))
        guard await until({ recorder.ready == [token] }) else { return [] }
        let json = (try? await evaluate(probe, in: controller)) as? String ?? "[]"
        return (try? JSONDecoder().decode([Double].self, from: Data(json.utf8))) ?? []
    }

    private func check(style: ThemeStyle, dark: Bool, token: Int) async {
        let seen = await measure(style: style, dark: dark, token: token)
        #expect(seen.count == 6, "seen: \(seen)")
        guard seen.count == 6 else { return }
        #expect(abs(seen[0]) < 0.5, "signature text is \(seen[0]) px from the message text's left")
        #expect(abs(seen[1]) < 0.5, "the dotted rule starts \(seen[1]) px from the article's left edge")
        #expect(seen[2] == 10, "right padding of the text: \(seen[2])")
        #expect(abs(seen[3]) < 0.5, "signature and text share the right inset: \(seen[3])")
        #expect(seen[4] == 0, "a quote has no rule above or below: \(seen[4])")
        #expect(abs(seen[5]) < 0.5, "the dotted rule ends \(seen[5]) px from the article's right edge")
    }

    @Test func modernLight() async { await check(style: .modern, dark: false, token: 1) }
    @Test func modernDark() async { await check(style: .modern, dark: true, token: 2) }
    @Test func classicLight() async { await check(style: .classic, dark: false, token: 3) }
    @Test func classicDark() async { await check(style: .classic, dark: true, token: 4) }
}
