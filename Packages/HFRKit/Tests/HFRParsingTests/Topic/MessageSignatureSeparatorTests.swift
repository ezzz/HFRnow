import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// HFR's separator before a signature (#755): the first text inside `span.signature` is a space and 15 dashes (capture
/// `R267a`, #267). Legacy removed every 15-dash string of the message (`LinkItem.m:74` @ 87fe0d1c); SwiftHFR drops only
/// that leading one, so dashes a member typed stay.
@Suite("Signature separator")
struct MessageSignatureSeparatorTests {
    @Test("R267a: the separator in front of each signature is gone, the signature text stays")
    func captureSeparatorDropped() throws {
        let blocks = try MessageBlockParser.blocks(in: Fixture.capture("R267a-topic-signature-separator-anon"))
        var checked = 0
        for block in blocks {
            let content = try MessageContentNormalizer.normalize(contentHTML: block.contentHTML)
            guard let signature = content.signatureHTML else { continue }
            checked += 1
            #expect(!signature.contains("---------------"))
            #expect(signature.contains("Signature removed."))
        }
        #expect(checked > 0)
    }

    @Test("A body line made of dashes is kept (hand-built fragment, not a capture)")
    func bodyDashesKept() throws {
        let html = "<div id=\"para1\">above<br />---------------<br />below"
            + "<span class=\"signature\"> ---------------\n\t\t\t<br />Signature removed.<div style=\"clear: both;\"> </div></span></div>"
        let content = try MessageContentNormalizer.normalize(contentHTML: html)
        #expect(content.html.contains("---------------"))
        #expect(content.signatureHTML?.contains("---------------") == false)
        #expect(content.signatureHTML?.contains("Signature removed.") == true)
    }

    @Test("Dashes a member typed inside a signature, after its first text, are kept (hand-built fragment)")
    func signatureOwnDashesKept() throws {
        let html = "<span class=\"signature\"> ---------------\n<br />a<br />---------------<br />b</span>"
        let content = try MessageContentNormalizer.normalize(contentHTML: html)
        #expect(content.signatureHTML?.components(separatedBy: "---------------").count == 2)
    }

    @Test("A signature without HFR's separator is untouched (R20 markup)")
    func noSeparator() throws {
        let content = try MessageContentNormalizer.normalize(contentHTML: "<span class=\"signature\">Signature removed.</span>")
        #expect(content.signatureHTML == "Signature removed.")
    }

    @Test("A run of 14 or 16 dashes opening a signature is not HFR's separator and stays (hand-built fragments)",
          arguments: [14, 16])
    func otherRunsKept(count: Int) throws {
        let run = String(repeating: "-", count: count)
        let content = try MessageContentNormalizer.normalize(
            contentHTML: "<span class=\"signature\"> \(run)\n<br />Signature removed.</span>"
        )
        #expect(content.signatureHTML?.contains(run) == true)
    }

    @Test("A signature made only of the separator leaves its line break, as legacy's empty block (hand-built, not captured)")
    func separatorOnly() throws {
        let content = try MessageContentNormalizer.normalize(contentHTML: "<span class=\"signature\"> ---------------\n<br /></span>")
        #expect(content.signatureHTML == "<br />")
    }
}
