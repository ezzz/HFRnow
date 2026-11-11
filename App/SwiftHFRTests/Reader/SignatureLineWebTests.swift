import Foundation
import HFRModels
import HFRParsing
@testable import SwiftHFR
import Testing
import UIKit
import WebKit

/// #755 in the real web view, on the captured page `R267a` (#267): HFR's dashes before a signature are gone and one thin
/// solid line, as wide as the message, sets the signature apart.
@MainActor
@Suite(.serialized)
struct SignatureLineWebTests: ReaderWebTesting {
    private static let pageURL = url("https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm")

    static func signedMessage() throws -> ReaderMessage {
        let data = try LiveTopicPageSourceTests.capture("R267a-topic-signature-separator-anon.html")
        let page = try LiveTopicPageSource.parse(
            try #require(String(data: data, encoding: .utf8)), pageURL: pageURL, normalizer: LiveContentNormalizer()
        )
        return try #require(page.messages.first { $0.content.signatureHTML != nil })
    }

    @Test func aCapturedSignatureHasNoDashesAndOneThinFullWidthLine() async throws {
        let message = try Self.signedMessage()
        let (controller, recorder) = makeController(transport: imageTransport())
        let page = ReaderPage(topicID: readerTopic, title: "Titre", currentPage: 1, maxPage: 1, messages: [message])
        controller.show(ReaderDocument(
            token: 1, html: TopicHTMLBuilder.document(for: page, token: 1, options: ReaderRenderOptions(showsSignatures: true)),
            anchor: nil, keepsScrollPosition: false
        ))
        #expect(await until { recorder.ready == [1] })
        let script = """
            const sig = document.querySelector('.signature');
            const style = getComputedStyle(sig);
            return [sig.textContent, style.borderTopStyle, style.borderTopWidth, sig.getBoundingClientRect().width,
                    document.querySelector(".content").getBoundingClientRect().width];
            """
        let values = try #require(try await evaluate(script, in: controller) as? [Any])
        let text = try #require(values[0] as? String)
        #expect(!text.contains("--") && text.contains("Signature removed."))
        #expect(values[1] as? String == "solid")
        #expect(values[2] as? String == "1px")
        let width = try #require((values[3] as? NSNumber)?.doubleValue)
        let container = try #require((values[4] as? NSNumber)?.doubleValue)
        #expect(width > 0 && abs(width - container) < 1, "the line is as wide as the message text")
    }
}
