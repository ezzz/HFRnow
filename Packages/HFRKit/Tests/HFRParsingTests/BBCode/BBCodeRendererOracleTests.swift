import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// ADR 0014 §2: for every captured pair, the renderer's output equals the LOT-034 normalization of HFR's own rendering,
/// field by field. Two kinds of pair exist in the corpus: HFR's preview (`POST /apercu.php`, `R95d`, `R95h`) of a
/// posted source (`W61`, `W62`), and the quote prefill of a message (`R41a`, `R42`: the stored source, as HFR gives it
/// back, HTML-escaped in the textarea) against its rendering on the thread page (`R20`). The reductions are listed on
/// each helper; every one is counted (LESSONS 51). The `\r` HFR leaves in the text is compared like any character.
@Suite("BBCode renderer against HFR's own rendering")
struct BBCodeRendererOracleTests {
    /// The `content_form` value of a captured write, form-decoded (CRLF line breaks, as the browser sent them).
    static func postedSource(_ capture: String, field: String = "content_form") throws -> String {
        let meta = try Fixture.capture(capture, extension: "json")
        let object = try JSONSerialization.jsonObject(with: Data(meta.utf8)) as? [String: Any]
        let body = try #require(object?["request_body"] as? String)
        let value = try #require(body.split(separator: "&").first { $0.hasPrefix(field + "=") })
        return try #require(value.dropFirst(field.count + 1).replacing("+", with: " ").removingPercentEncoding)
    }

    /// The message body of an `/apercu.php` answer in the thread page's shape: the inner HTML of `body.reponse`
    /// without the template's own leading line break, prefixed with the `<p>` the thread adds (`R20` `para2666649`
    /// against the `R41a` review; measured on the raw pages of #400).
    static func previewBody(_ capture: String) throws -> String {
        let page = try Fixture.capture(capture)
        let start = try #require(page.firstRange(of: "<body"))
        let open = try #require(page[start.upperBound...].firstRange(of: ">"))
        let end = try #require(page.firstRange(of: "</body>"))
        var body = String(page[open.upperBound..<end.lowerBound])
        if body.hasPrefix("\n") { body.removeFirst() }
        return "<p>" + body
    }

    /// The content of a message block of a topic capture (`div#para<numreponse>`, as `MessageBlockParser` reads it).
    static func threadBody(_ capture: String, numreponse: Int) throws -> String {
        let block = try #require(try MessageBlockParser.blocks(in: Fixture.capture(capture)).first { $0.numreponse == numreponse })
        return block.contentHTML
    }

    /// The source of a message as its quote form gives it back, without the `[quotemsg=…]` wrapper and the trailing
    /// line break HFR adds, its textarea entities decoded (`&amp;` of cited links, HFR-PROTOCOL §6b "Quote prefill";
    /// `R95c` shows `&amp; &#034;` for a source `& "`). The prefill writes an image as `[url]` (`R41a` byte 58565
    /// against `R20` byte 14838), so `imageURLs` names the URLs to give back to `[img]`; the per-fixture pseudonyms of
    /// the anonymizer (FIXTURES.md: consistent within a fixture) are mapped with `renames`.
    static func prefillSource(
        _ capture: String, numreponse: Int, imageURLs: [URL], renames: [String: String] = [:]
    ) throws -> String {
        let page = try Fixture.capture(capture)
        let marker = "[quotemsg=\(numreponse),"
        let start = try #require(page.firstRange(of: marker))
        let open = try #require(page[start.upperBound...].firstRange(of: "]"))
        let end = try #require(page[open.upperBound...].firstRange(of: "[/quotemsg]"))
        var source = String(page[open.upperBound..<end.lowerBound])
        // The `textarea` escapes the source: 12 `&amp;` in the prefill of 2666649 (cited links), none in the others.
        #expect(source.matches(of: /&amp;/).count == (capture.hasPrefix("R41a") ? 12 : 0))
        source = source.replacing("&lt;", with: "<").replacing("&gt;", with: ">").replacing("&#034;", with: "\"")
            .replacing("&quot;", with: "\"").replacing("&amp;", with: "&")
        for (old, new) in renames {
            #expect(source.contains(old))
            source = source.replacing(old, with: new)
        }
        for url in imageURLs {
            let link = "[url]\(url.absoluteString)[/url]"
            #expect(source.contains(link))
            source = source.replacing(link, with: "[img]\(url.absoluteString)[/img]")
        }
        return source
    }

    /// HFR's rendering normalized. `colourSpans` counts the `[cpp]` syntax-colour spans unwrapped from it: the renderer
    /// writes a plain code block (LOT-097 spec, intentional difference 3).
    static func oracle(contentHTML: String, colourSpans: Int = 0) throws -> MessageContent {
        var content = try MessageContentNormalizer.normalize(contentHTML: contentHTML)
        let spans = content.html.matches(of: /<span style="color:[a-z]+">([^<]*)<\/span>/)
        #expect(spans.count == colourSpans)
        for span in spans.reversed() {
            content.html.replaceSubrange(span.range, with: span.output.1)
        }
        return content
    }

    /// The bundled catalogue as the app will pass it, plus the personal smileys the pairs use.
    static func smileys(personal: [String] = []) throws -> [String: URL] {
        var table = Dictionary(try CommonSmileyCatalog.bundled().map { ($0.code, $0.url) }, uniquingKeysWith: { first, _ in first })
        for name in personal {
            table["[:\(name)]"] = try #require(URL(string: "https://forum-images.hardware.fr/images/perso/\(name).gif"))
        }
        return table
    }

    /// Field by field, `\r` included.
    static func expectEqual(_ actual: MessageContent, _ expected: MessageContent) {
        #expect(actual.html == expected.html)
        #expect(actual.links == expected.links)
        #expect(actual.images == expected.images)
        #expect(actual.smileys == expected.smileys)
        #expect(actual.embeds == expected.embeds)
        #expect(actual.signatureHTML == nil && expected.signatureHTML == nil)
    }

    @Test("W61 (every toolbar tag) renders as HFR's preview R95d")
    func toolbarTags() throws {
        let source = try Self.postedSource("W61.meta")
        #expect(try Self.postedSource("R95d.meta", field: "apercu_contenu") == source)
        #expect(source.contains("\r\n[b]bold[/b]\r\n"))
        let expected = try Self.oracle(contentHTML: Self.previewBody("R95d-apercu-bbcode-preview"), colourSpans: 1)
        Self.expectEqual(try BBCodeRenderer.render(source), expected)
        // Not vacuous (LESSONS 51): two links, one image on a smiley path, no other image, four blocks.
        #expect(expected.links.count == 2 && expected.smileys.count == 1 && expected.images.isEmpty)
        #expect(expected.html.contains("<table class=\"spoiler\">") && expected.html.contains("<ol class=\"olcode\">"))
    }

    @Test("W62 (BMP emoji) renders as HFR's preview R95h")
    func emoji() throws {
        let source = try Self.postedSource("W62.meta")
        #expect(try Self.postedSource("R95h.meta", field: "apercu_contenu") == source)
        let expected = try Self.oracle(contentHTML: Self.previewBody("R95h-apercu-bmp-emoji-preview"))
        Self.expectEqual(try BBCodeRenderer.render(source), expected)
        #expect(expected.html.contains("\u{2764}\u{FE0F}"))
    }

    @Test("R41a (quote prefill of message 2666649) renders as the thread page R20: colour, crossed tags, blank lines, smileys")
    func recipeMessage() throws {
        // The thread page holds 37 `<strong>` and 37 `</strong>` for the 37 `[b]` / `[/b]` of the prefill; the in-page
        // parse of a crossed `</span></strong>` followed by `&nbsp;` reopens a `<strong>` (`contentHTML` serializes
        // 37 opens for 36 closes, the normalizer 38 for 38), which the renderer reproduces by writing the entity and
        // parsing its string in the same context (`BBCodeRenderer.contentHTML`).
        let thread = try Self.threadBody("R20-topic-p1-anon", numreponse: 2_666_649)
        #expect(thread.matches(of: /<strong>/).count == 37 && thread.matches(of: /<\/strong>/).count == 36)
        let expected = try Self.oracle(contentHTML: thread)
        // The prefill writes every image of the message as `[url]`: given back to the URLs the thread shows as images.
        let source = try Self.prefillSource("R41a-quote-form", numreponse: 2_666_649, imageURLs: expected.images.map(\.url))
        #expect(expected.images.count == 11)
        #expect(source.contains("[#0055aa] [u][b]La pizza Napolitaine[/u][/b][/#0055aa] \r\n\r\n\r\n"))
        #expect(source.contains("[/url]  :ange: \r\n"))
        let page = try #require(URL(string: "https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm"))
        let actual = try BBCodeRenderer.render(source, options: BBCodeRenderOptions(smileys: Self.smileys()), relativeTo: page)
        Self.expectEqual(actual, expected)
        #expect(expected.smileys.map(\.code).contains(":ange:") && expected.links.count > 10)
        let crossed = "<span style=\"color:#0055aa\"> <span class=\"u\"><strong>La pizza Napolitaine</strong></span></span>"
        #expect(expected.html.contains(crossed))
    }

    @Test("R42 (quote prefill of message 2666682) renders as the thread page R20: image, blank line, smiley typed in lower case")
    func smileyCaseMessage() throws {
        // The anonymizer maps the member's folder name per fixture (`user38` in `R42`, `user37` in `R20`).
        let expected = try Self.oracle(contentHTML: Self.threadBody("R20-topic-p1-anon", numreponse: 2_666_682))
        let source = try Self.prefillSource(
            "R42-multiquote-form-cookie", numreponse: 2_666_682, imageURLs: expected.images.map(\.url), renames: ["user38": "user37"]
        )
        #expect(source.hasSuffix("pas fan :d") && expected.images.count == 1)
        let actual = try BBCodeRenderer.render(source, options: BBCodeRenderOptions(smileys: Self.smileys()))
        Self.expectEqual(actual, expected)
        #expect(expected.smileys.map(\.code) == [":d"])
        #expect(expected.html.contains("alt=\":d\" title=\":D\""))
    }

    @Test("R41b (quote prefill of message 2666695): a personal smiley renders as on the thread page R20")
    func personalSmiley() throws {
        // The prefill drops the citation the message starts with; its own text follows. `[:user5]` in `R41b` is
        // `[:user6]` in `R20` (per-fixture pseudonyms).
        let source = try Self.prefillSource(
            "R41b-quote-form-of-quoting-post", numreponse: 2_666_695, imageURLs: [], renames: ["user5": "user6"]
        )
        #expect(source == "\r\n\r\ns'pas une pizza alors [:user6]")
        let thread = try Self.threadBody("R20-topic-p1-anon", numreponse: 2_666_695)
        let own = try #require(thread.firstRange(of: "</div><p>"))
        let trailer = try #require(thread[own.upperBound...].firstRange(of: "<div style=\"clear: both;\">"))
        let expected = try Self.oracle(contentHTML: "<p>" + thread[own.upperBound..<trailer.lowerBound])
        let actual = try BBCodeRenderer.render(source, options: BBCodeRenderOptions(smileys: Self.smileys(personal: ["user6"])))
        Self.expectEqual(actual, expected)
        #expect(expected.smileys.map(\.kind) == [.custom])
    }
}
