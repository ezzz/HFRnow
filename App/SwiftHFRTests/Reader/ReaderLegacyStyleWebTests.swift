import Foundation
import HFRModels
@testable import SwiftHFR
import Testing
import UIKit

/// The legacy message look by default (#819), measured in the real reader. Values are the legacy ones at `87fe0d1c`:
/// body indent per style (`MessagesView.swift:1827`), 15 pt text over a 17 pt body style (`MessagesView.swift:675-682`, 873),
/// 2 px quote border without fill (`style-liste.css:329-334`), no paragraph margin (`style-liste.css:40-45`), 10 px under the
/// body (`style-liste-light.css:495-499`), grey silhouette when there is no avatar (`style-liste-light.css:203-205`).
@MainActor
@Suite(.serialized)
struct ReaderLegacyStyleWebTests: ReaderWebTesting {
    private func page(token: Int, style: ThemeStyle) -> ReaderDocument {
        let message = ReaderMessage(
            numreponse: 1, author: "auteur", isDeleted: false, isContinuation: false, avatarURL: nil,
            dateText: "27-10-2026 10:00:00", editNote: nil, quotedByCount: nil,
            content: MessageContent(html: """
                <table class="quote"><tr><td><b class="s1">cite :</b><p>cité</p></td></tr></table><p>un</p><p>deux</p>
                """)
        )
        let page = ReaderPage(topicID: readerTopic, title: "Titre", currentPage: 1, maxPage: 1, messages: [message])
        let html = TopicHTMLBuilder.document(for: page, token: token, options: ReaderRenderOptions(style: style))
        return ReaderDocument(token: token, html: html, anchor: nil, keepsScrollPosition: false)
    }

    /// [body text size / root, indent of the body text minus the pseudo's left edge, quote border width, quote fill alpha,
    ///  gap between two paragraphs, padding under the body text, silhouette is drawn (1) and initials hidden (1)].
    private let probe = """
        const root = parseFloat(getComputedStyle(document.documentElement).fontSize);
        const content = document.querySelector('.content'), cs = getComputedStyle(content);
        const textLeft = content.getBoundingClientRect().left + parseFloat(cs.paddingLeft) + parseFloat(cs.borderLeftWidth);
        const author = document.querySelector('.author').getBoundingClientRect().left;
        const quote = getComputedStyle(document.querySelector('table.quote'));
        const alpha = quote.backgroundColor.startsWith('rgba') ? parseFloat(quote.backgroundColor.split(',')[3]) : 1;
        const paragraphs = document.querySelectorAll('.content > p');
        const gap = paragraphs[1].getBoundingClientRect().top - paragraphs[0].getBoundingClientRect().bottom;
        const avatar = getComputedStyle(document.querySelector('.avatar-default'));
        const silhouette = avatar.backgroundImage.includes('radial-gradient') && avatar.color === 'rgba(0, 0, 0, 0)';
        return JSON.stringify([parseFloat(cs.fontSize) / root, textLeft - author, parseFloat(quote.borderLeftWidth), alpha, gap,
                               parseFloat(cs.paddingBottom), silhouette ? 1 : 0]);
        """

    private func measure(style: ThemeStyle, token: Int) async -> [Double] {
        let (controller, recorder) = makeController(transport: imageTransport())
        recorder.window?.overrideUserInterfaceStyle = .light
        controller.show(page(token: token, style: style))
        guard await until({ recorder.ready == [token] }) else { return [] }
        let json = (try? await evaluate(probe, in: controller)) as? String ?? "[]"
        return (try? JSONDecoder().decode([Double].self, from: Data(json.utf8))) ?? []
    }

    @Test func theModernStyleIndentsTheBodyUnderThePseudoAndTightensEverything() async {
        let seen = await measure(style: .modern, token: 1)
        #expect(seen.count == 7, "seen: \(seen)")
        guard seen.count == 7 else { return }
        #expect(abs(seen[0] - 15.0 / 17.0) < 0.01, "text size ratio: \(seen[0])")
        #expect(abs(seen[1]) < 1.5, "body text left of the pseudo by \(seen[1]) px")
        #expect(seen[2] == 2, "quote border: \(seen[2])")
        #expect(seen[3] == 0, "quote fill alpha: \(seen[3])")
        #expect(seen[4] == 0, "gap between paragraphs: \(seen[4])")
        #expect(seen[5] == 10, "padding under the body: \(seen[5])")
        #expect(seen[6] == 1, "silhouette: \(seen[6])")
    }

    // Legacy classic is the flat style: the body starts 10 px from the edge, as the header does, without the indent.
    @Test func theClassicStyleKeepsTheBodyFlat() async {
        let seen = await measure(style: .classic, token: 2)
        #expect(seen.count == 7, "seen: \(seen)")
        guard seen.count == 7 else { return }
        #expect(seen[1] < -20, "classic body must sit left of the pseudo, flat: \(seen[1])")
        #expect(abs(seen[0] - 15.0 / 17.0) < 0.01, "text size ratio: \(seen[0])")
        #expect(seen[2] == 2 && seen[3] == 0 && seen[4] == 0)
    }
}
