import Foundation
import HFRModels
@testable import SwiftHFR
import Testing
import UIKit

/// #1439 in the real reader: at the accessibility Dynamic Type sizes the message text started about 40 % of an iPhone's width
/// from the edge (the 1em article padding plus a 2.7rem indent, both following the body size). They now stop at the largest
/// non-accessibility size (body 23 px), as legacy's fixed 52 px never grew (`MessagesView.swift:1827` @ 87fe0d1c); below it the
/// page is unchanged. The page's body size is set the way `-apple-system-body` sets it, on `<html>`.
@MainActor
@Suite(.serialized)
struct ReaderAccessibilitySizeWebTests: ReaderWebTesting {
    private func document(token: Int, style: ThemeStyle) -> ReaderDocument {
        let message = ReaderMessage(
            numreponse: 1, author: "auteur", isDeleted: false, isContinuation: false, avatarURL: nil,
            dateText: "27-10-2026 10:00:00", editNote: nil, quotedByCount: nil,
            content: MessageContent(html: "<p>Ce topic a pour but de référencer les topics uniques</p>", signatureHTML: "<br />signature")
        )
        let page = ReaderPage(topicID: readerTopic, title: "Titre", currentPage: 1, maxPage: 1, messages: [message])
        let options = ReaderRenderOptions(showsSignatures: true, style: style)
        return ReaderDocument(
            token: token, html: TopicHTMLBuilder.document(for: page, token: token, options: options), anchor: nil,
            keepsScrollPosition: false
        )
    }

    /// [message text left minus article left, signature text left minus message text left] with `<html>` at `bodySize` px.
    private func measure(bodySize: Int, style: ThemeStyle, token: Int) async -> [Double] {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.show(document(token: token, style: style))
        guard await until({ recorder.ready == [token] }) else { return [] }
        let probe = """
            document.documentElement.style.fontSize = '\(bodySize)px';
            const content = document.querySelector('.content'), cs = getComputedStyle(content);
            const textLeft = content.getBoundingClientRect().left + parseFloat(cs.paddingLeft) + parseFloat(cs.borderLeftWidth);
            const sig = document.querySelector('.signature'), ss = getComputedStyle(sig);
            const sigLeft = sig.getBoundingClientRect().left + parseFloat(ss.borderLeftWidth) + parseFloat(ss.paddingLeft);
            return JSON.stringify([textLeft - document.querySelector('article.message').getBoundingClientRect().left, sigLeft - textLeft]);
            """
        let json = (try? await evaluate(probe, in: controller)) as? String ?? "[]"
        return (try? JSONDecoder().decode([Double].self, from: Data(json.utf8))) ?? []
    }

    /// Accessibility-XL (`accessibility-extra-large`, body 40 px): the text starts no further than 23 px of padding plus the
    /// 2.7 × 23 px indent (85.1 px), not at 148 px; the signature keeps the text's inset.
    @Test func theModernIndentStopsGrowingAtTheAccessibilitySizes() async {
        let seen = await measure(bodySize: 40, style: .modern, token: 1)
        #expect(seen.count == 2, "seen: \(seen)")
        guard seen.count == 2 else { return }
        #expect(abs(seen[0] - (23 + 2.7 * 23)) < 0.5, "the text starts \(seen[0]) px from the page's edge")
        #expect(abs(seen[1]) < 0.5, "the signature text is \(seen[1]) px from the message text's left")
    }

    @Test func theClassicPaddingStopsGrowingAtTheAccessibilitySizes() async {
        let seen = await measure(bodySize: 40, style: .classic, token: 2)
        #expect(seen.count == 2, "seen: \(seen)")
        guard seen.count == 2 else { return }
        #expect(abs(seen[0] - 23) < 0.5, "the text starts \(seen[0]) px from the page's edge")
        #expect(abs(seen[1]) < 0.5, "the signature text is \(seen[1]) px from the message text's left")
    }

    /// Guard: the default size (body 17 px) and the largest non-accessibility one (23 px) keep 1em plus 2.7rem.
    @Test(arguments: [17, 23])
    func theModernIndentIsUnchangedUpToTheLargestStandardSize(bodySize: Int) async {
        let seen = await measure(bodySize: bodySize, style: .modern, token: 3 + bodySize)
        #expect(seen.count == 2, "seen: \(seen)")
        guard seen.count == 2 else { return }
        let expected = Double(bodySize) * 3.7
        #expect(abs(seen[0] - expected) < 0.5, "the text starts \(seen[0]) px from the page's edge, \(expected) expected")
    }
}
