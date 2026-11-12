import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// ADR 0014 §2 against the batch 2 previews of #443 (`R443a`-`R443n`, `POST /apercu.php`, nothing posted), one test per
/// numbered fact of #742. The pair is the preview's own `apercu_contenu` and the body HFR answers, normalized as in
/// `BBCodeRendererOracleTests`; a reduction is named and counted (LESSONS 51).
@Suite("BBCode renderer against HFR's batch 2 previews (#443)")
struct BBCodeRendererBatch2OracleTests {
    typealias Oracle = BBCodeRendererOracleTests

    /// The lines of a capture's `apercu_contenu`, `nil` for a line the anonymizer damaged (`R443c`, `R443f`: an address
    /// after `[email]` / `[url]mailto:` is replaced by `%redacted@…`, which no longer decodes).
    static func sourceLines(_ capture: String) throws -> [String?] {
        let meta = try Fixture.capture(capture + ".meta", extension: "json")
        let object = try JSONSerialization.jsonObject(with: Data(meta.utf8)) as? [String: Any]
        let body = try #require(object?["request_body"] as? String)
        let field = try #require(body.split(separator: "&").first { $0.hasPrefix("apercu_contenu=") })
        let value = field.dropFirst("apercu_contenu=".count).replacing("+", with: " ")
        return value.components(separatedBy: "%0D%0A").map { $0.removingPercentEncoding }
    }

    /// The whole `apercu_contenu`, CRLF-joined (the capture has no damaged line).
    static func source(_ capture: String) throws -> String {
        let lines = try sourceLines(capture)
        #expect(lines.allSatisfy { $0 != nil })
        return lines.compactMap { $0 }.joined(separator: "\r\n")
    }

    /// The raw message of an `/apercu.php` answer: the body without the template's leading line break and clear trailer.
    static func rawBody(_ capture: String) throws -> String {
        var body = try Oracle.previewBody(capture)
        body.removeFirst(3)
        let trailer = try #require(body.range(of: "<div style=\"clear: both;\"> </div>"))
        return String(body[..<trailer.lowerBound])
    }

    /// The catalogue as the app passes it, plus what these previews use: the two personal smileys of the account, and the
    /// codes `:p:` and `:D:` HFR knows (`R443n`) while the bundled catalogue does not (#742, follow-up issue).
    static func table() throws -> [String: URL] {
        var table = try Oracle.smileys()
        for (code, path) in [
            ("[:user1]", "images/perso/user1.gif"), ("[:user1:1]", "images/perso/1/user1.gif"),
            (":p:", "icones/smilies/p.gif"), (":D:", "icones/smilies/D.gif")
        ] {
            table[code] = try #require(URL(string: "https://forum-images.hardware.fr/" + path))
        }
        return table
    }

    static func render(_ source: String) throws -> MessageContent {
        try BBCodeRenderer.render(source, options: BBCodeRenderOptions(smileys: table()))
    }

    /// HFR's quote of these previews is `table.oldquote` with `hr` borders, normalized to a classless table; the renderer
    /// writes the `table.quote` + `br` shape of `R95d` (two captures disagree, follow-up issue). Mapped, and counted.
    static func quoteShapeMapped(_ html: String, quotes: Int) -> String {
        let head = "<table><tbody><tr class=\"none\"><td><b class=\"s1\">Citation :</b><hr />"
        let tail = "<hr /></td></tr></tbody></table></div>"
        #expect(html.matches(of: /<table><tbody><tr class="none"><td><b class="s1">Citation :<\/b><hr \/>/).count == quotes)
        #expect(html.components(separatedBy: tail).count - 1 == quotes)
        return html
            .replacing(head, with: "<table class=\"quote\"><tbody><tr class=\"none\"><td><b class=\"s1\">Citation :</b><br /><br />")
            .replacing(tail, with: "</td></tr></tbody></table></div>")
    }

    @Test("Fact 1: [code] is coloured like [cpp]: keywords, // comments with the line's CR; [c] [java] [php] [html] are text (R443e)")
    func syntaxColours() throws {
        let expected = try Oracle.oracle(contentHTML: Oracle.previewBody("R443e-apercu-syntax-colours"))
        let actual = try Self.render(Self.source("R443e"))
        Oracle.expectEqual(actual, expected)
        #expect(expected.html.matches(of: /<span style="color:blue">/).count == 10)
        #expect(expected.html.matches(of: /<span style="color:green"><i>\/\/ comment\r<\/i><\/span>/).count == 2)
        #expect(expected.html.contains("[c]int x;[/c]") && expected.html.contains("[html]&lt;b&gt;x&lt;/b&gt;[/html]"))
    }

    @Test("Fact 2: tags inside a raw block (R443j, R443n)")
    func tagsInRawBlocks() throws {
        // `[b]` in `[code]` is rendered (R443j); the preview's last line, `[quotemsg]`, is another fact (follow-up).
        let source = try Self.source("R443j")
        let cutSource = try #require(source.range(of: "\r\n[quotemsg"))
        let body = try Self.rawBody("R443j-apercu-malformed-misc")
        let cutBody = try #require(body.range(of: "\r<br /></p><div class=\"container\"><table class=\"oldcitation\""))
        let expected = try Oracle.oracle(contentHTML: "<p>" + body[..<cutBody.lowerBound])
        let actual = try Self.render(String(source[..<cutSource.lowerBound]))
        Oracle.expectEqual(actual, expected)
        #expect(expected.html.contains("<li><strong>x</strong></li>"))
        // The three nestings and the closing of `[code][code]` (R443n), whole.
        let nested = try Oracle.oracle(contentHTML: Oracle.previewBody("R443n-apercu-pending-defaults"))
        Oracle.expectEqual(try Self.render(Self.source("R443n")), nested)
        #expect(nested.html.contains("<li>c <table class=\"code\">") && nested.html.contains("<li>c <table class=\"fixed\">"))
        #expect(nested.html.contains("&lt;span style=\"color:blue\"&gt;<span style=\"color:blue\">int</span>&lt;/span&gt; y;"))
        #expect(nested.html.contains("<li>a [code]b</li>") && !nested.html.contains("[fixed]f"))
    }

    @Test("Fact 3: [b][/b] is text; a [b] around or across a quote loses its tags and the quote renders (R443i, R443j)")
    func boldAndQuotes() throws {
        let preview = try Self.rawBody("R443i-apercu-malformed-crossing")
        let expected = try Oracle.oracle(contentHTML: "<p>" + preview)
        var mapped = expected
        mapped.html = Self.quoteShapeMapped(expected.html, quotes: 2)
        Oracle.expectEqual(try Self.render(Self.source("R443i")), mapped)
        #expect(expected.html.matches(of: /<strong>/).count == 1 && expected.html.matches(of: /Citation :/).count == 2)
        let empty = try Self.render("empty [b][/b] bold")
        #expect(empty.html == "<p>empty [b][/b] bold</p>")
    }

    @Test("Fact 4: of 30 nested quotes only the two outer levels render; the other opens and closes stay text (R443l)")
    func quoteDepth() throws {
        let expected = try Oracle.oracle(contentHTML: Oracle.previewBody("R443l-apercu-quote-30-nested"))
        var mapped = expected
        mapped.html = Self.quoteShapeMapped(expected.html, quotes: 2)
        Oracle.expectEqual(try Self.render(Self.source("R443l")), mapped)
        #expect(expected.html.matches(of: /\[quote\]/).count == 28 && expected.html.matches(of: /\[\/quote\]/).count == 28)
    }

    @Test("Fact 5: smileys (R443a, R443n)")
    func smileys() throws {
        let expected = try Oracle.oracle(contentHTML: Oracle.previewBody("R443a-apercu-smileys-on"))
        let actual = try Self.render(Self.source("R443a"))
        Oracle.expectEqual(actual, expected)
        #expect(expected.html.contains("<a href=\"https://example.invalid/\" class=\"cLink\">https://example.invalid/</a><img"))
        #expect(expected.html.contains("[url]https://example.invalid/<img") && expected.html.contains("\"oui\" ) &amp; )"))
        // Overlapping codes, `:p:pfff:` (R443n, with the two codes HFR knows).
        let overlap = try Self.render(":p:pfff: :D:dtc:")
        #expect(overlap.smileys.map(\.code) == [":p:", ":D:"] && overlap.html.contains("pfff: ") && overlap.html.hasSuffix("dtc:</p>"))
    }

    @Test("Fact 6: a colour closes at the first colour close, whatever its name; the inner open stays text (R443c, R443n)")
    func colours() throws {
        // R443c: the first four lines; its `[email]` line is damaged in the capture (follow-up).
        let lines = try Self.sourceLines("R443c")
        #expect(lines.prefix(4).allSatisfy { $0 != nil })
        let body = try Self.rawBody("R443c-apercu-colour-email")
        let cut = try #require(body.range(of: "\r<br />email tag:"))
        let expected = try Oracle.oracle(contentHTML: "<p>" + body[..<cut.lowerBound])
        let actual = try Self.render(lines.prefix(4).compactMap { $0 }.joined(separator: "\r\n"))
        Oracle.expectEqual(actual, expected)
        #expect(expected.html.contains("<span style=\"color:#f00\">court</span>") && expected.html.contains("[color=red]rouge[/color]"))
        let nested = try Self.render("[#0055AA]x[/#0055aa] [#ff0000]a [#00ff00]b[/#00ff00] c[/#ff0000]")
        #expect(nested.html == "<p><span style=\"color:#0055AA\">x</span> "
            + "<span style=\"color:#ff0000\">a [#00ff00]b</span> c[/#ff0000]</p>")
    }

    @Test("Fact 7: whitespace: the message start is not a line start; a single leading space of a code line stays plain (R443g, R443n)")
    func whitespace() throws {
        let expected = try Oracle.oracle(contentHTML: Oracle.previewBody("R443g-apercu-whitespace"))
        Oracle.expectEqual(try Self.render(Self.source("R443g")), expected)
        #expect(expected.html.hasPrefix("<p> &nbsp; starts with three spaces"))
        #expect(expected.html.contains("<li> leading space in code</li>") && expected.html.contains("<li>a&nbsp; b&nbsp; &nbsp;c</li>"))
        #expect(expected.html.contains("<br />&nbsp;one leading space") && expected.html.hasSuffix("<br />&nbsp;<br />&nbsp;<br /></p>"))
    }

    @Test("Fact 8: consecutive [*] lines make one list; [list] stays text; the line's CR ends the item, its LF is dropped (R443d)")
    func bullets() throws {
        let expected = try Oracle.oracle(contentHTML: Oracle.previewBody("R443d-apercu-bullets"))
        Oracle.expectEqual(try Self.render(Self.source("R443d")), expected)
        #expect(expected.html.matches(of: /<ul>/).count == 3 && expected.html.contains("<li>one\r</li><li>two\r</li><li>three\r</li>"))
        #expect(expected.html.contains("[list]") && expected.html.contains("<li>\r</li></ul><p>end"))
    }

    @Test("Fact 9: URLs, line by line (R443f): equal to HFR except `tel:` (difference 2)")
    func urls() throws {
        let body = try Self.rawBody("R443f-apercu-url-schemes")
        let segments = body.components(separatedBy: "\r<br />")
        let lines = try Self.sourceLines("R443f")
        #expect(segments.count == lines.count)
        var differing: [Int] = []
        for (index, (line, segment)) in zip(lines, segments).enumerated() {
            guard let line else { continue }
            let expected = try Oracle.oracle(contentHTML: "<p>" + segment)
            let actual = try Self.render(line)
            if actual.html != expected.html || actual.links != expected.links || actual.images != expected.images {
                differing.append(index)
            }
        }
        // Both sides go through the normalizer, which drops `ftp://`, `javascript:` and `//host` alike: the one line that
        // differs is `[url]tel:0123[/url]`, which HFR turns into `http://tel:0123`, a valid URL the normalizer keeps as a
        // link, while the renderer leaves `tel:` as typed and the sanitizer unwraps it (intentional difference 2). Line 4
        // (`[url]mailto:…`) is damaged in the capture and skipped.
        #expect(differing == [3])
        #expect(lines[4] == nil && lines.compactMap { $0 }.count == 15)
    }

    @Test("R443b (smileys off), R443h (nesting), R443k (quote never closed)")
    func otherCaptures() throws {
        let off = try Oracle.oracle(contentHTML: Oracle.previewBody("R443b-apercu-smileys-off"))
        let options = BBCodeRenderOptions(smileysEnabled: false, smileys: try Self.table())
        let actual = try BBCodeRenderer.render(Self.source("R443b"), options: options)
        #expect(actual.smileys.isEmpty && off.smileys.isEmpty)
        #expect(actual.html == off.html && off.html.contains("\"oui\" ) &amp; )"))
        let nesting = try Oracle.oracle(contentHTML: Oracle.previewBody("R443h-apercu-nesting"))
        var mapped = nesting
        mapped.html = Self.quoteShapeMapped(nesting.html, quotes: 4)
        Oracle.expectEqual(try Self.render(Self.source("R443h")), mapped)
        let open = try Oracle.oracle(contentHTML: Oracle.previewBody("R443k-apercu-quote-never-closed"))
        Oracle.expectEqual(try Self.render(Self.source("R443k")), open)
        #expect(open.html.contains("[quote]never closed"))
    }
}
