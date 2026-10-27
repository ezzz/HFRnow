import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// Rules of `MessageContentNormalizer` on the LOT-001 captures (facts in HFR-PROTOCOL §6c, LOT-034) and the sanitization
/// contract of ADR 0006 on inline snippets (no page state involved).
@Suite("Message content normalizer")
struct MessageContentNormalizerTests {
    static let imageHost = "https://forum-images.hardware.fr"

    // MARK: - Captures

    @Test("R20 message 2: signature split out, personal and standard smileys, quote header link, external link")
    func signatureAndSmileys() throws {
        let content = try Self.content("R20-topic-p1-anon", index: 2)
        #expect(content.signatureHTML == "Signature removed.")
        #expect(!content.html.contains("signature"))
        #expect(!content.html.contains("clear: both"), "HFR's layout trailer is dropped")
        #expect(content.html.hasSuffix("<br />"), "the break before the signature stays, as legacy kept it")
        #expect(content.smileys == [
            MessageSmiley(code: ":d", url: try Self.url("\(Self.imageHost)/icones/biggrin.gif"), kind: .standard),
            MessageSmiley(code: "[:user6]", url: try Self.url("\(Self.imageHost)/images/perso/user6.gif"), kind: .custom)
        ])
        #expect(content.html.contains(
            "<img src=\"\(Self.imageHost)/images/perso/user6.gif\" alt=\"[:user6]\" title=\"[:user6]\" class=\"smileycustom\" />"
        ))
        let quoted = "https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm#t2666682"
        let external = "http://bibi.hn.org/~bibi/user37/P0002208.JPG"
        #expect(content.links == [
            MessageLink(url: try Self.url(quoted), text: "user4 a écrit :"),
            MessageLink(url: try Self.url(external), text: external)
        ])
        #expect(content.images.isEmpty)
        #expect(content.html.contains(
            "<table class=\"citation\"><tbody><tr class=\"none\"><td><b class=\"s1\"><a href=\"\(quoted)\" class=\"Topic\">"
        ))
        #expect(content.html.contains("<br />&nbsp;<br />"), "non-breaking spaces stay entities")
        #expect(!content.html.contains("rel=") && !content.html.contains("target="))
    }

    @Test("R28 message 2: bare images become typed images without a link, their onload and style dropped")
    func bareImages() throws {
        let content = try Self.content("R28-topic-images-videos-anon", index: 2)
        #expect(content.images.count == 2)
        #expect(content.images.allSatisfy { $0.linkURL == nil && !$0.isInSignature && $0.altText == $0.url.absoluteString })
        let last = "https://i.redd.it/5faawd26qexh1.jpeg"
        #expect(content.images.last?.url.absoluteString == last)
        #expect(content.html.contains("<img src=\"\(last)\" alt=\"\(last)\" title=\"\(last)\" class=\"hfrplusimg\" />"))
        #expect(!content.html.contains("onload") && !content.html.contains("margin"))
        #expect(content.signatureHTML != nil)
    }

    @Test("R28: an image inside a link carries the link as its target, and that link is not listed twice")
    func linkedImages() throws {
        let blocks = try MessageBlockParser.blocks(in: Fixture.capture("R28-topic-images-videos-anon"))
        let contents = try blocks.map { try MessageContentNormalizer.normalize(contentHTML: $0.contentHTML) }
        let linked = contents.flatMap(\.images).filter { $0.linkURL != nil }
        #expect(linked.count == 16, "the capture holds 16 `a.cLink > img` pairs")
        #expect(linked.first?.url.absoluteString == "https://i85.servimg.com/u/f85/17/46/59/69/hstlet10.jpg")
        #expect(linked.first?.linkURL?.absoluteString == "https://servimg.com/view/17465969/5442")
        for content in contents {
            for image in content.images where image.linkURL != nil {
                #expect(!content.links.contains { $0.url == image.linkURL && $0.text.isEmpty }, "the wrapping link is the image's own")
            }
        }
    }

    @Test("R27 message 7: the spoiler keeps its markup and loses its onclick and style; the edit trailer is dropped")
    func spoiler() throws {
        let content = try Self.content("R27-topic-spoilers-anon", index: 7)
        #expect(content.html.contains(
            "<table class=\"spoiler\"><tbody><tr class=\"none\"><td><b class=\"s1Topic\">Spoiler :</b><br /><br />"
                + "<div class=\"Topic masque\">"
        ))
        #expect(!content.html.contains("onclick") && !content.html.contains("cursor"))
        #expect(!content.html.contains("Message cité"), "div.edited is LOT-030's trailer, not content")
        #expect(content.smileys.map(\.code) == ["[:user13]"])
    }

    @Test("R27b message 0: code blocks keep their lines, colours and entities; ids and fonts go")
    func codeBlock() throws {
        let content = try Self.content("R27b-topic-code-blocks-anon", index: 0)
        #expect(content.html.contains(
            "<table class=\"code\"><tbody><tr class=\"none\"><td><b class=\"s1\">Code :</b><br /><ol class=\"olcode\">"
                + "<li><span style=\"color:blue\">#include</span> \"windows.h\"</li><li></li>"
        ))
        let comment =
            /<span style="color:green"><i>\/\/ 0\. Définir la page de code de la console en UTF-8 \(65001\)\s<\/i><\/span>/
        #expect(content.html.firstMatch(of: comment) != nil, "the line break of the comment is kept")
        #expect(!content.html.contains("id=\"code1\"") && !content.html.contains("font-family"))
        #expect(content.smileys.map(\.code) == [":o", ":sol:"])
    }

    @Test("Every message of the corpus normalizes; the signature is never empty; smileys are never images")
    func wholeCorpus() throws {
        let map = try TopicOracle.loadMap()
        for caseID in MessageBlockOracleTests.cases {
            let entry = try #require(map[caseID])
            for block in try MessageBlockParser.blocks(in: TopicOracle.capture(for: entry)) {
                let content = try MessageContentNormalizer.normalize(contentHTML: block.contentHTML)
                // A literal: a `Comment` value is ambiguous with SwiftSoup's `Comment` in the macro expansion on Linux.
                let label = "\(caseID) \(block.numreponse)"
                #expect(content.signatureHTML != "", "\(label)")
                #expect(content.images.allSatisfy { MessageContentNormalizer.smileyKind(of: $0.url) == nil }, "\(label)")
                #expect(content.smileys.allSatisfy { $0.url.scheme == "https" }, "\(label)")
            }
        }
    }

    // MARK: - Helpers

    static func content(_ capture: String, index: Int) throws -> MessageContent {
        let blocks = try MessageBlockParser.blocks(in: Fixture.capture(capture))
        return try MessageContentNormalizer.normalize(contentHTML: blocks[index].contentHTML)
    }

    static func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }
}
