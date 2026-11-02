import Foundation
import Testing
@testable import HFRParsing

/// The rules of `HFRBBCodeWriter` on inline sources, each cited to the capture that shows it (LOT-097 spec "Rendering
/// table" and "Edge cases"); the whole pairs are checked by `BBCodeRendererOracleTests`.
@Suite("HFR BBCode writer")
struct HFRBBCodeWriterTests {
    static let writer = HFRBBCodeWriter(smileysEnabled: true, smileys: [:])

    static func html(_ source: String) -> String { writer.html(for: source) }

    @Test("Inline tags, nesting and crossing come out as HFR writes them (R95d, R41a → R20)")
    func inlineTags() {
        #expect(Self.html("[b]x[/b] [i]y[/i] [u]z[/u] [strike]s[/strike]")
            == "<p><strong>x</strong> <em>y</em> <span class=\"u\">z</span> <strike>s</strike></p>")
        #expect(Self.html("[b][i]nested[/i][/b]") == "<p><strong><em>nested</em></strong></p>")
        #expect(Self.html("[u][b]La pizza[/u][/b]") == "<p><span class=\"u\"><strong>La pizza</span></strong></p>")
        #expect(Self.html("[#0055aa] [u][b]t[/u][/b][/#0055aa] \r\n")
            == "<p><span style=\"color:#0055aa\"> <span class=\"u\"><strong>t</span></strong></span> \u{A0}<br /></p>")
    }

    @Test(
        "Brackets that are not a matched known tag are text (R95d: [color=], [list], an unclosed [b])",
        arguments: [
            "[b]unclosed", "[/b]", "[i]x[/b]", "[color=#FF0000]red[/color]", "[list]", "[/list]", "[B]x[/B]", "[ b ]x[/ b ]",
            "[b", "b]", "[]", "[url=]x[/url]", "[email]a@b.c[/email]", "[#FF0000]x[/#00FF00]", "[#F00]x[/#F00]", "a[b]c",
            "[b\nx]y[/b]", "[url=https://a.example/\nx]y[/url]", "[img][/img]", "[url][/url]", "[quote]never closed"
        ]
    )
    func unmatchedIsText(source: String) {
        let expected = "<p>" + HFRBBCodeWriter.escape(source).replacing("\n", with: "\r<br />") + "</p>"
        #expect(Self.html(source) == expected)
    }

    @Test("Blocks close the paragraph and reopen it; a quote body ends with a break, a spoiler body does not (R95d)")
    func blocks() {
        #expect(Self.html("a\r\n[quote]q[/quote]\r\nb")
            == "<p>a\r<br /></p><div class=\"container\"><table class=\"quote\"><tr class=\"none\"><td><b class=\"s1\">Citation :</b>"
            + "<br /><br /><p>q<br /></p></td></tr></table></div><p>\r<br />b</p>")
        #expect(Self.html("[spoiler]s[/spoiler]")
            == "<p></p><div class=\"container\"><table class=\"spoiler\"><tr class=\"none\"><td><b class=\"s1Topic\">Spoiler :</b>"
            + "<br /><br /><div class=\"Topic masque\"><p>s</p></div></td></tr></table></div><p></p>")
        #expect(Self.html("[quote][quote]in[/quote]out[/quote]").contains("<p>in<br /></p></td></tr></table></div><p>out<br /></p>"))
        #expect(Self.html("[fixed]a  b\r\nc[/fixed]")
            == "<p></p><table class=\"fixed\"><tr class=\"none\"><td><p>a \u{A0}b\r<br />c</p></td></tr></table><p></p>")
        #expect(Self.html("[code]a\r\n\r\n   b[/code]")
            == "<p></p><table class=\"code\"><tr class=\"none\"><td><b class=\"s1\">Code :</b><br />"
            + "<ol class=\"olcode\"><li>a</li><li></li><li>\u{A0} \u{A0}b</li></ol></td></tr></table><p></p>")
        #expect(Self.html("[code]code   text[/code]").contains("<li>code\u{A0} \u{A0}text</li>"))
        #expect(Self.html("[cpp]int x;[/cpp]").contains("<ol class=\"olcode\"><li>int x;</li></ol>"))
        #expect(Self.html("[code][b]x[/b] &lt;[/code]").contains("<li>[b]x[/b] &amp;lt;</li>"))
    }

    @Test("Bullets: the first [*] of a line opens ul > li for the rest of the line and eats its break (R95d)")
    func bullets() {
        #expect(Self.html("[list]\r\n[*]item one[*]item two[/list]\r\n[b]n[/b]")
            == "<p>[list]\r<br /></p><ul><li>item one[*]item two[/list]\r</li></ul><p><strong>n</strong></p>")
        #expect(Self.html("[*]a\r\n[*]b") == "<p></p><ul><li>a\r</li></ul><p></p><ul><li>b</li></ul><p></p>")
    }

    @Test("Links and images: both url forms, the whole element final (R95d)")
    func linksAndImages() {
        #expect(Self.html("[url]https://a.example/?x=1&y=2[/url]")
            == "<p><a href=\"https://a.example/?x=1&amp;y=2\" class=\"cLink\">https://a.example/?x=1&amp;y=2</a></p>")
        #expect(Self.html("[url=https://a.example/]link [b]text[/b][/url]")
            == "<p><a href=\"https://a.example/\" class=\"cLink\">link <strong>text</strong></a></p>")
        #expect(Self.html("[img]https://a.example/i.png[/img]")
            == "<p><img src=\"https://a.example/i.png\" alt=\"https://a.example/i.png\" title=\"https://a.example/i.png\" /></p>")
        #expect(Self.html("[url]https://a.example/[/url]  :ange: x")
            == "<p><a href=\"https://a.example/\" class=\"cLink\">https://a.example/</a> \u{A0}:ange: x</p>")
    }

    @Test("Whitespace: a space or CR after a whitespace is a no-break space; blank lines and trailing spaces (R20, R27b)")
    func whitespace() {
        #expect(Self.html("a  b") == "<p>a \u{A0}b</p>")
        #expect(Self.html("a \r\n\r\n\r\n b") == "<p>a \u{A0}<br />\u{A0}<br />\u{A0}<br />\u{A0}b</p>")
        #expect(Self.html("Bonjour,\r\n\r\nPour") == "<p>Bonjour,\r<br />\u{A0}<br />Pour</p>")
        #expect(Self.html(")  \r\n\r\n* on") == "<p>) \u{A0}\r<br />\u{A0}<br />* on</p>")
        #expect(Self.html("(pro)   5.75") == "<p>(pro) \u{A0} 5.75</p>")
        #expect(Self.html("x\r\n         y") == "<p>x\r<br />\u{A0} \u{A0} \u{A0} \u{A0} \u{A0}y</p>")
        #expect(Self.html("[url=https://a.example/] napoletana [/url]")
            == "<p><a href=\"https://a.example/\" class=\"cLink\">napoletana</a></p>")
        #expect(Self.html("[url]G3Ferrari / Optima [/url]")
            == "<p><a href=\"http://G3Ferrari / Optima \" class=\"cLink\">G3Ferrari / Optima</a></p>")
        #expect(Self.html("[url=www.a.example/x]t[/url]") == "<p><a href=\"http://www.a.example/x\" class=\"cLink\">t</a></p>")
        #expect(Self.html("a\nb\rc") == "<p>a\r<br />b\r<br />c</p>")
        #expect(Self.html("") == "<p></p>")
    }

    @Test("Smileys: longest code first, any case, alt as typed and title as the catalogue (R20: alt=':d' title=':D')")
    func smileys() throws {
        let url = try #require(URL(string: "https://forum-images.hardware.fr/icones/biggrin.gif"))
        let smile = try #require(URL(string: "https://forum-images.hardware.fr/icones/smile.gif"))
        let perso = try #require(URL(string: "https://forum-images.hardware.fr/images/perso/user6.gif"))
        let writer = HFRBBCodeWriter(smileysEnabled: true, smileys: [":D": url, ":)": smile, "[:user6]": perso])
        #expect(writer.html(for: "fan :d :D :) [:user6]")
            == "<p>fan <img src=\"https://forum-images.hardware.fr/icones/biggrin.gif\" alt=\":d\" title=\":D\" /> "
            + "<img src=\"https://forum-images.hardware.fr/icones/biggrin.gif\" alt=\":D\" title=\":D\" /> "
            + "<img src=\"https://forum-images.hardware.fr/icones/smile.gif\" alt=\":)\" title=\":)\" /> "
            + "<img src=\"https://forum-images.hardware.fr/images/perso/user6.gif\" alt=\"[:user6]\" title=\"[:user6]\" /></p>")
        #expect(writer.html(for: "[url]https://a.example/:)[/url]").contains("cLink\">https://a.example/:)</a>"))
        let off = HFRBBCodeWriter(smileysEnabled: false, smileys: [":D": url])
        #expect(off.html(for: ":D") == "<p>:D</p>")
    }

    @Test("Escaping: the four characters HFR escapes, and nothing else, once (R95d)")
    func escaping() {
        #expect(Self.html("plain <b>html</b> & \"quotes\" 'x'") == "<p>plain &lt;b&gt;html&lt;/b&gt; &amp; &#034;quotes&#034; 'x'</p>")
        #expect(Self.html("a\u{FFFF}b") == "<p>ab</p>")
    }
}
