import Foundation
import HFRModels
import SwiftSoup
import Testing
@testable import HFRParsing

/// The sanitization contract of ADR 0006 (and amendment 1) checked by `MessageContentNormalizer` on inline snippets:
/// no page state is involved, every case is an input HFR could serve or an attacker could post.
@Suite("Message content sanitization")
struct MessageContentSanitizationTests {
    static let imageHost = MessageContentNormalizerTests.imageHost

    @Test(
        "A link with a rejected scheme is unwrapped to its text",
        arguments: [
            "javascript:alert(1)", "JaVaScRiPt:alert(1)", "java\nscript:alert(1)", "java\tscript:alert(1)", " javascript:alert(1)",
            "&#106;avascript:alert(1)", "&#x6A;avascript:alert(1)", "data:text/html,x", "file:///etc/passwd", "blob:https://x/y",
            "vbscript:x", "https://forum.hardware.fr@evil.example/", "", "%6Aavascript:alert(1)"
        ]
    )
    func rejectedLinkSchemes(href: String) throws {
        let content = try MessageContentNormalizer.normalize(contentHTML: "<p>see <a href=\"\(href)\" class=\"cLink\">here</a>!</p>")
        #expect(content.html == "<p>see here!</p>")
        #expect(content.links.isEmpty)
    }

    @Test(
        "An image with a rejected scheme is removed",
        arguments: ["javascript:alert(1)", "data:image/png;base64,AAAA", "file:///x.png", "blob:https://x/y", "", "//"]
    )
    func rejectedImageSchemes(src: String) throws {
        let html = "<p>a<img src=\"\(src)\" alt=\"x\" onerror=\"alert(1)\">b</p>"
        let content = try MessageContentNormalizer.normalize(contentHTML: html)
        #expect(content.html == "<p>ab</p>")
        #expect(content.images.isEmpty && content.smileys.isEmpty)
    }

    @Test("Protocol-relative and relative links resolve against the page, http forum links become https")
    func linkResolution() throws {
        let page = try Self.url("https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_3.htm")
        let html = """
            <a href="//example.org/x">a</a><a href="#t12">b</a><a href="/hfr/x.htm">c</a>\
            <a href="http://forum.hardware.fr/forum2.php?cat=1">d</a><a href="HTTP://FORUM-IMAGES.hardware.fr/i.gif">e</a>\
            <a href="http://forum.hardware.fr:8080/x">f</a>
            """
        let content = try MessageContentNormalizer.normalize(contentHTML: html, relativeTo: page)
        #expect(content.links.map(\.url.absoluteString) == [
            "https://example.org/x",
            "https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_3.htm#t12",
            "https://forum.hardware.fr/hfr/x.htm",
            "https://forum.hardware.fr/forum2.php?cat=1",
            "https://forum-images.hardware.fr/i.gif",
            "http://forum.hardware.fr:8080/x"
        ])
        #expect(content.links.map(\.text) == ["a", "b", "c", "d", "e", "f"])
    }

    @Test("hfr-rehost.net images and links are served from reho.st (legacy LinkItem.m:163; pending capture)")
    func rehostHost() throws {
        let html = "<a href=\"http://hfr-rehost.net/self/a.jpg\"><img src=\"https://www.hfr-rehost.net/thumb/a.jpg\" alt=\"\"></a>"
        let content = try MessageContentNormalizer.normalize(contentHTML: html)
        #expect(content.images.map(\.url.absoluteString) == ["https://www.reho.st/thumb/a.jpg"])
        #expect(content.images.map(\.linkURL?.absoluteString) == ["http://reho.st/self/a.jpg"])
        #expect(content.links.isEmpty)
        #expect(content.html
            == "<a href=\"http://reho.st/self/a.jpg\"><img src=\"https://www.reho.st/thumb/a.jpg\" alt=\"\" class=\"hfrplusimg\" /></a>")
    }

    @Test("Event handlers, ids, unknown attributes and unknown classes are dropped; style survives only as a colour on span")
    func attributes() throws {
        let html = """
            <p id="p1" onclick="x()" class="evil s1" data-x="1"><span style="color:#0055aa" onmouseover="x()">a</span>\
            <span style="color:red;background:url(x)">b</span><span style="color:expression(x)">c</span>\
            <span style="position:fixed">d</span><span style=" COLOR : Blue ; ">e</span><span style="color:#12345">f</span>\
            <b style="font-family:x" class="s1">g</b><table class="citation" onclick="x()" width="100%"><tr><td>h</td></tr></table></p>
            """
        let content = try MessageContentNormalizer.normalize(contentHTML: html)
        #expect(content.html == "<p class=\"s1\"><span style=\"color:#0055aa\">a</span><span>b</span><span>c</span><span>d</span>"
            + "<span style=\"color:Blue\">e</span><span>f</span><b class=\"s1\">g</b></p>"
            + "<table class=\"citation\"><tbody><tr><td>h</td></tr></tbody></table>")
    }

    @Test("Dangerous elements go with their content, unknown ones are unwrapped, comments vanish")
    func elements() throws {
        let html = """
            <p>a<script>alert(1)</script><style>p{}</style><iframe src="https://x"></iframe><object data="x"></object>\
            <svg onload="x()"><a href="javascript:x">s</a></svg><!-- c -->\
            <font color="red">f</font><marquee>m</marquee><u>u</u><strike>s</strike></p>\
            <form><input value="i"></form><center>g</center><h3>h</h3>
            """
        let content = try MessageContentNormalizer.normalize(contentHTML: html)
        #expect(content.html == "<p>afm<u>u</u><strike>s</strike></p>gh")
        #expect(content.links.isEmpty)
    }

    @Test("Text and attribute values are escaped by the serializer, whatever the page wrote")
    func escaping() throws {
        let html = "<p>&lt;b&gt; &amp;amp; \"q\" <a href=\"https://x.example/?a=1&amp;b=2\" title=\"&quot;t&quot; &lt;i&gt;\">l</a></p>"
        let content = try MessageContentNormalizer.normalize(contentHTML: html)
        // SwiftSoup's base escape mode writes `<` raw inside a quoted attribute value: the normalizer removes it instead.
        #expect(content.html
            == "<p>&lt;b&gt; &amp;amp; \"q\" <a href=\"https://x.example/?a=1&amp;b=2\" title=\"&quot;t&quot; i\">l</a></p>")
        #expect(content.links.map(\.url.absoluteString) == ["https://x.example/?a=1&b=2"])
    }

    @Test("Smileys are told apart from images by host and path; the code is the alt as served")
    func smileyKinds() throws {
        let html = """
            <img src="\(Self.imageHost)/icones/smilies/ange.gif" alt=":ange:" title=":ange:">\
            <img src="http://forum-images.hardware.fr/icones/redface.gif" alt=":o" title=":o">\
            <img src="\(Self.imageHost)/images/perso/3/[:it's me]" alt="[:it's me]" title="[:it's me]">\
            <img src="\(Self.imageHost)/themes_static/images_forum/1/quote+.gif" alt="answer +">\
            <img src="\(Self.imageHost)/icones/x.gif">
            """
        let content = try MessageContentNormalizer.normalize(contentHTML: html)
        #expect(content.smileys.map(\.code) == [":ange:", ":o", "[:it's me]", ""])
        #expect(content.smileys.map(\.kind) == [.standard, .standard, .custom, .standard])
        #expect(content.smileys[1].url.absoluteString == "\(Self.imageHost)/icones/redface.gif")
        #expect(content.smileys[2].url.absoluteString == "\(Self.imageHost)/images/perso/3/%5B:it's%20me%5D")
        #expect(content.images.map(\.url.absoluteString)
            == ["\(Self.imageHost)/themes_static/images_forum/1/quote+.gif"])
        #expect(content.html.contains("class=\"smileycustom\"") && !content.html.contains("class=\"smileycustom\" alt"))
    }

    @Test("The first signature is split out, later ones are dropped, contents inside it are flagged")
    func signatures() throws {
        let html = """
            <p>body <a href="https://a.example/">A</a></p><br><span class="signature"><br>sig <a href="https://s.example/">S</a>\
            <img src="https://i.example/s.png" alt="i"><span class="signature">nested</span></span>\
            <p>after</p><span class="signature">second</span>
            """
        let content = try MessageContentNormalizer.normalize(contentHTML: html)
        #expect(content.html == "<p>body <a href=\"https://a.example/\">A</a></p><br /><p>after</p>")
        #expect(content.signatureHTML
            == "<br />sig <a href=\"https://s.example/\">S</a><img src=\"https://i.example/s.png\" alt=\"i\" class=\"hfrplusimg\" />")
        #expect(content.links.map(\.isInSignature) == [false, true])
        #expect(content.images.map(\.isInSignature) == [true])
    }

    @Test("signatureHTML is nil without a signature, and when the signature span has no content left")
    func noSignature() throws {
        #expect(try MessageContentNormalizer.normalize(contentHTML: "<p>x</p>").signatureHTML == nil)
        #expect(try MessageContentNormalizer.normalize(contentHTML: "<p>x</p><span class=\"signature\"></span>").signatureHTML == nil)
        let dropped = "<p>x</p><span class=\"signature\"><script>s()</script><img src=\"javascript:x\"></span>"
        #expect(try MessageContentNormalizer.normalize(contentHTML: dropped).signatureHTML == nil)
        #expect(try MessageContentNormalizer.normalize(contentHTML: "<span class=\"signature\"> </span>").signatureHTML == " ")
    }

    @Test("Angle brackets never reach an attribute value; the typed lists keep the text as served")
    func attributeAngleBrackets() throws {
        let html = "<img src=\"https://i.example/a.png\" alt=\"&quot;&gt;<b>x</b>\" title=\"a<b\">"
            + "<a href=\"https://a.example/\" title=\"&lt;t&gt;\">l</a>"
        let content = try MessageContentNormalizer.normalize(contentHTML: html)
        #expect(content.html == "<img src=\"https://i.example/a.png\" alt=\"&quot;bx/b\" title=\"ab\" class=\"hfrplusimg\" />"
            + "<a href=\"https://a.example/\" title=\"t\">l</a>")
        #expect(content.images.map(\.altText) == ["\"><b>x</b>"])
        #expect(content.html.firstMatch(of: /="[^"]*[<>][^"]*"/) == nil, "no < or > inside any attribute value")
    }

    @Test("Deep nesting is normalized on a background thread's stack, where a recursive walk would overflow")
    func deepNesting() async throws {
        let depth = 10_000
        let bold = String(repeating: "<b>", count: depth) + "x" + String(repeating: "</b>", count: depth)
        let nested = depth / 5
        let mixed = String(repeating: "<div><p><a href=\"https://a.example/\">", count: nested) + "y"
        let (boldContent, mixedContent) = try await Task.detached {
            (try MessageContentNormalizer.normalize(contentHTML: bold), try MessageContentNormalizer.normalize(contentHTML: mixed))
        }.value
        #expect(try Self.text(of: boldContent.html) == "x")
        #expect(boldContent.html.hasPrefix(String(repeating: "<b>", count: 50)))
        #expect(try Self.text(of: mixedContent.html) == "y")
        // The tree builder reopens an `<a>` around the block it cannot contain, so the exact link count is its own;
        // every link is finished after its children and the innermost one carries the text.
        #expect(mixedContent.links.count >= nested)
        #expect(mixedContent.links.contains { $0.text == "y" })
    }

    @Test("The clear trailer and empty paragraphs are dropped; a div with that style but content stays as a plain div")
    func trailers() throws {
        let html = "<p></p><p>a<div style=\"clear: both;\"> </div></p><div style=\"clear:both\"></div>"
            + "<div style=\"clear: both;\">text</div><div class=\"container\" style=\"clear: both;\">c</div>"
            + "<div class=\"edited\">Message cité 1 fois</div><p> </p>"
        let content = try MessageContentNormalizer.normalize(contentHTML: html)
        #expect(content.html == "<p>a</p><div>text</div><div class=\"container\">c</div><p> </p>")
    }

    @Test("A link whose only content is an image is the image's target; a link with text next to an image is a link")
    func imageLinks() throws {
        let html = """
            <a href="https://a.example/1"> <img src="https://i.example/1.png" alt="1"> </a>\
            <a href="https://a.example/2"><img src="https://i.example/2.png" alt="2">two</a>\
            <a href="https://a.example/3"><img src="https://i.example/3.png" alt="3"><img src="https://i.example/4.png" alt="4"></a>\
            <a href="https://a.example/4"><img src="\(Self.imageHost)/icones/x.gif" alt=":x:"></a>
            """
        let content = try MessageContentNormalizer.normalize(contentHTML: html)
        #expect(content.images.map { $0.linkURL?.absoluteString } == ["https://a.example/1", nil, nil, nil])
        #expect(content.links.map(\.url.absoluteString) == ["https://a.example/2", "https://a.example/3", "https://a.example/4"])
        #expect(content.links.map(\.text) == ["two", "", ""])
    }

    @Test("Empty input gives empty content; broken markup still normalizes")
    func emptyInput() throws {
        let empty = try MessageContentNormalizer.normalize(contentHTML: "")
        #expect(empty == MessageContent(html: ""))
        let broken = try MessageContentNormalizer.normalize(contentHTML: "<p><b>x</p></b><td>y")
        #expect(try Self.text(of: broken.html).contains("x") && broken.html.contains("y"))
    }

    // MARK: - Helpers

    static func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    static func text(of html: String) throws -> String {
        try SwiftSoup.parseBodyFragment(html).body()?.text() ?? ""
    }
}
