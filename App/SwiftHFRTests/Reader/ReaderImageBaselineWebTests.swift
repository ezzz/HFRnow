import Foundation
import HFRModels
@testable import SwiftHFR
import Testing
import UIKit

/// #1049 in the real reader: a smiley or inline image rests on the text baseline, as in legacy (its `style-liste*.css` sheets
/// set no `vertical-align` on message images, so they keep the default `baseline`; `style-smile.css`'s `middle` is the picker's).
@MainActor
@Suite(.serialized)
struct ReaderImageBaselineWebTests: ReaderWebTesting {
    private static let smiley = "https://forum-images.hardware.fr/icones/smile.gif"

    private func document(token: Int) -> ReaderDocument {
        let message = ReaderMessage(
            numreponse: 1, author: "auteur", isDeleted: false, isContinuation: false, avatarURL: nil,
            dateText: "27-10-2026 10:00:00", editNote: nil, quotedByCount: nil,
            content: MessageContent(
                html: "<p>du texte <img src=\"\(Self.smiley)\" width=\"40\" height=\"40\" alt=\":)\"> encore</p>",
                signatureHTML: "<br />sig <img src=\"\(Self.smiley)\" width=\"40\" height=\"40\" alt=\":)\">"
            )
        )
        let page = ReaderPage(topicID: readerTopic, title: "Titre", currentPage: 1, maxPage: 1, messages: [message])
        let html = TopicHTMLBuilder.document(for: page, token: token, options: ReaderRenderOptions(showsSignatures: true))
        return ReaderDocument(token: token, html: html, anchor: nil, keepsScrollPosition: false)
    }

    /// [computed vertical-align of the content smiley and of the signature smiley,
    ///  smiley bottom minus the line's baseline (content), same for the signature].
    private let probe = """
        const baseline = (el) => {
            const mark = document.createElement('span');
            mark.style.cssText = 'display: inline-block; width: 0; height: 0; vertical-align: baseline';
            el.parentNode.insertBefore(mark, el.nextSibling);
            const line = mark.getBoundingClientRect().bottom;
            mark.remove();
            return el.getBoundingClientRect().bottom - line;
        };
        const smiley = document.querySelector('.content img'), sig = document.querySelector('.signature img');
        return JSON.stringify([getComputedStyle(smiley).verticalAlign, getComputedStyle(sig).verticalAlign,
                               baseline(smiley), baseline(sig)]);
        """

    @Test func smileysRestOnTheTextBaseline() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.show(document(token: 1))
        #expect(await until { recorder.ready == [1] })
        let json = try #require(try await evaluate(probe, in: controller) as? String)
        let seen = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any])
        #expect(seen[0] as? String == "baseline", "content smiley: \(seen[0])")
        #expect(seen[1] as? String == "baseline", "signature smiley: \(seen[1])")
        let content = try #require((seen[2] as? NSNumber)?.doubleValue)
        let signature = try #require((seen[3] as? NSNumber)?.doubleValue)
        #expect(abs(content) <= 1, "the smiley's bottom is \(content) px from the baseline")
        #expect(abs(signature) <= 1, "the signature smiley's bottom is \(signature) px from the baseline")
    }
}
