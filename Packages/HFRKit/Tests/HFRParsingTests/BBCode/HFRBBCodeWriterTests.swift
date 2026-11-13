import Foundation
import HFRModels
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
            == "<p><strong>x</strong> <em>y</em> <span class=\"u\">z</span> <strike>s</strike>")
        #expect(Self.html("[b][i]nested[/i][/b]") == "<p><strong><em>nested</em></strong>")
        #expect(Self.html("[u][b]La pizza[/u][/b]") == "<p><span class=\"u\"><strong>La pizza</span></strong>")
        #expect(Self.html("[#0055aa] [u][b]t[/u][/b][/#0055aa] \r\n")
            == "<p><span style=\"color:#0055aa\"> <span class=\"u\"><strong>t</span></strong></span> &nbsp;<br />")
    }

    @Test(
        "Brackets that are not a matched known tag are text (R95d: [color=], [list], an unclosed [b])",
        arguments: [
            "[b]unclosed", "[/b]", "[i]x[/b]", "[color=#FF0000]red[/color]", "[list]", "[/list]", "[B]x[/B]", "[ b ]x[/ b ]",
            "[b", "b]", "[]", "[url=]x[/url]", "[email]a@b.c[/email]", "a[b]c",
            "[b\nx]y[/b]", "[url=https://a.example/\nx]y[/url]", "[img][/img]", "[url][/url]", "[quote]never closed"
        ]
    )
    func unmatchedIsText(source: String) {
        let escaped = HFRBBCodeWriter.string(HFRBBCodeWriter.escape(HFRBBCodeWriter.scalars(source)))
        let expected = "<p>" + escaped.replacing("\n", with: "\r<br />")
        #expect(Self.html(source) == expected)
    }

    @Test("Blocks close the paragraph and reopen it; a quote body ends with a break, a spoiler body does not (R95d)")
    func blocks() {
        #expect(Self.html("a\r\n[quote]q[/quote]\r\nb")
            == "<p>a\r<br /></p><div class=\"container\"><table class=\"quote\"><tr class=\"none\"><td><b class=\"s1\">Citation :</b>"
            + "<br /><br /><p>q<br /></p></td></tr></table></div><p>\r<br />b")
        #expect(Self.html("[spoiler]s[/spoiler]")
            == "<p></p><div class=\"container\"><table class=\"spoiler\"><tr class=\"none\"><td><b class=\"s1Topic\">Spoiler :</b>"
            + "<br /><br /><div class=\"Topic masque\"><p>s</p></div></td></tr></table></div><p>")
        #expect(Self.html("[quote][quote]in[/quote]out[/quote]").contains("<p>in<br /></p></td></tr></table></div><p>out<br />"))
        #expect(Self.html("[fixed]a  b\r\nc[/fixed]")
            == "<p></p><table class=\"fixed\"><tr class=\"none\"><td><p>a &nbsp;b\r<br />c</p></td></tr></table><p>")
        #expect(Self.html("[code]a\r\n\r\n   b[/code]")
            == "<p></p><table class=\"code\"><tr class=\"none\"><td><b class=\"s1\">Code :</b><br />"
            + "<ol class=\"olcode\"><li>a</li><li></li><li>&nbsp; &nbsp;b</li></ol></td></tr></table><p>")
        #expect(Self.html("[code]code   text[/code]").contains("<li>code&nbsp; &nbsp;text</li>"))
        #expect(Self.html("[cpp]int x;[/cpp]").contains("<ol class=\"olcode\"><li><span style=\"color:blue\">int</span> x;</li></ol>"))
        // `[b]` is rendered in `code` (R443j), the rest of the content stays as typed.
        #expect(Self.html("[code][b]x[/b] &lt;[/code]").contains("<li><strong>x</strong> &amp;lt;</li>"))
        #expect(Self.html("[code][b][/b][/code]").contains("<li>[b][/b]</li>"))
    }

    @Test("Bullets: the first [*] of a line opens ul > li for the rest of the line and eats its break (R95d)")
    func bullets() {
        #expect(Self.html("[list]\r\n[*]item one[*]item two[/list]\r\n[b]n[/b]")
            == "<p>[list]\r<br /></p><ul><li>item one[*]item two[/list]\r</li></ul><p><strong>n</strong>")
        // Consecutive `[*]` lines are one list, the first line without one ends it, an empty `[*]` is an empty item (R443d).
        #expect(Self.html("[*]a\r\n[*]b") == "<p></p><ul><li>a\r</li><li>b</li></ul><p>")
        #expect(Self.html("[*]a\r\n[*]\r\nz\r\n[*]c") == "<p></p><ul><li>a\r</li><li>\r</li></ul><p>z\r<br /></p><ul><li>c</li></ul><p>")
        #expect(Self.html("[*]a\r\n\r\nb") == "<p></p><ul><li>a\r</li></ul><p>\r<br />b")
    }

    @Test("Links and images: both url forms, the whole element final (R95d)")
    func linksAndImages() {
        #expect(Self.html("[url]https://a.example/?x=1&y=2[/url]")
            == "<p><a href=\"https://a.example/?x=1&amp;y=2\" class=\"cLink\">https://a.example/?x=1&amp;y=2</a>")
        #expect(Self.html("[url=https://a.example/]link [b]text[/b][/url]")
            == "<p><a href=\"https://a.example/\" class=\"cLink\">link <strong>text</strong></a>")
        #expect(Self.html("[img]https://a.example/i.png[/img]")
            == "<p><img src=\"https://a.example/i.png\" alt=\"https://a.example/i.png\" title=\"https://a.example/i.png\" />")
        #expect(Self.html("[url]https://a.example/[/url]  :ange: x")
            == "<p><a href=\"https://a.example/\" class=\"cLink\">https://a.example/</a> &nbsp;:ange: x")
    }

    @Test("Whitespace: a space or CR after a whitespace is a no-break space; blank lines and trailing spaces (R20, R27b)")
    func whitespace() {
        #expect(Self.html("a  b") == "<p>a &nbsp;b")
        #expect(Self.html("a \r\n\r\n\r\n b") == "<p>a &nbsp;<br />&nbsp;<br />&nbsp;<br />&nbsp;b")
        #expect(Self.html("Bonjour,\r\n\r\nPour") == "<p>Bonjour,\r<br />&nbsp;<br />Pour")
        #expect(Self.html(")  \r\n\r\n* on") == "<p>) &nbsp;\r<br />&nbsp;<br />* on")
        #expect(Self.html("(pro)   5.75") == "<p>(pro) &nbsp; 5.75")
        #expect(Self.html("x\r\n         y") == "<p>x\r<br />&nbsp; &nbsp; &nbsp; &nbsp; &nbsp;y")
        #expect(Self.html("[url=https://a.example/] napoletana [/url]")
            == "<p><a href=\"https://a.example/\" class=\"cLink\">napoletana</a>")
        #expect(Self.html("[url]G3Ferrari / Optima [/url]")
            == "<p><a href=\"http://G3Ferrari / Optima \" class=\"cLink\">G3Ferrari / Optima</a>")
        #expect(Self.html("[url=www.a.example/x]t[/url]") == "<p><a href=\"http://www.a.example/x\" class=\"cLink\">t</a>")
        #expect(Self.html("[url]tel:0123[/url]") == "<p><a href=\"tel:0123\" class=\"cLink\">tel:0123</a>")
        #expect(Self.html("[url]www.a.example:8080/x[/url]")
            == "<p><a href=\"http://www.a.example:8080/x\" class=\"cLink\">www.a.example:8080/x</a>")
        // A run of spaces inside a URL or a link text is written `&nbsp;` as everywhere, never a marker.
        #expect(Self.html("[url]a  b[/url] [url=a  b]t  u[/url] [img]http://a  b[/img]")
            == "<p><a href=\"http://a &nbsp;b\" class=\"cLink\">a &nbsp;b</a> <a href=\"http://a &nbsp;b\" class=\"cLink\">t &nbsp;u</a> "
            + "<img src=\"http://a &nbsp;b\" alt=\"http://a &nbsp;b\" title=\"http://a &nbsp;b\" />")
        #expect(Self.html("a\nb\rc") == "<p>a\r<br />b\r<br />c")
        #expect(Self.html("") == "<p>")
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
            + "<img src=\"https://forum-images.hardware.fr/images/perso/user6.gif\" alt=\"[:user6]\" title=\"[:user6]\" />")
        let off = HFRBBCodeWriter(smileysEnabled: false, smileys: [":D": url])
        #expect(off.html(for: ":D") == "<p>:D")
        // Two codes equal once folded: the one typed exactly wins, else the first of the table.
        let both = HFRBBCodeWriter(smileysEnabled: true, smileys: [":d": smile, ":D": url])
        #expect(both.html(for: ":d :D :dd")
            == "<p><img src=\"https://forum-images.hardware.fr/icones/smile.gif\" alt=\":d\" title=\":d\" /> "
            + "<img src=\"https://forum-images.hardware.fr/icones/biggrin.gif\" alt=\":D\" title=\":D\" /> "
            + "<img src=\"https://forum-images.hardware.fr/icones/smile.gif\" alt=\":d\" title=\":d\" />d")
        // The longest code wins at a position (`:ouch:` over `:o`, `:pfff:` over `:p`; `R32a` renders `:pt1cable:` whole
        // while `:p` is a code); a partial longer code falls back to the shorter (`:ou` → `:o` + `u`); a bare prefix of
        // every code (`[:use]`) matches nothing; codes sharing a prefix (`[:user]`, `[:user:1]`) each match whole.
        let ouch = try #require(URL(string: "https://forum-images.hardware.fr/icones/smilies/ouch.gif"))
        let perso1 = try #require(URL(string: "https://forum-images.hardware.fr/images/perso/1/user.gif"))
        let longest = HFRBBCodeWriter(
            smileysEnabled: true,
            smileys: [":o": url, ":ouch:": ouch, ":p": url, ":pfff:": ouch, "[:user]": perso, "[:user:1]": perso1]
        )
        #expect(longest.html(for: ":ouch: :o :ou :pfff: [:user:1] [:user] [:use]")
            == "<p><img src=\"https://forum-images.hardware.fr/icones/smilies/ouch.gif\" alt=\":ouch:\" title=\":ouch:\" /> "
            + "<img src=\"https://forum-images.hardware.fr/icones/biggrin.gif\" alt=\":o\" title=\":o\" /> "
            + "<img src=\"https://forum-images.hardware.fr/icones/biggrin.gif\" alt=\":o\" title=\":o\" />u "
            + "<img src=\"https://forum-images.hardware.fr/icones/smilies/ouch.gif\" alt=\":pfff:\" title=\":pfff:\" /> "
            + "<img src=\"https://forum-images.hardware.fr/images/perso/1/user.gif\" alt=\"[:user:1]\" title=\"[:user:1]\" /> "
            + "<img src=\"https://forum-images.hardware.fr/images/perso/user6.gif\" alt=\"[:user]\" title=\"[:user]\" /> [:use]")
        // Two codes equal once folded and typed in a third case: the first in code-point order of the code (`:AB:` < `:ab:`).
        let tie = HFRBBCodeWriter(smileysEnabled: true, smileys: [":ab:": smile, ":AB:": url])
        #expect(tie.html(for: ":Ab:")
            == "<p><img src=\"https://forum-images.hardware.fr/icones/biggrin.gif\" alt=\":Ab:\" title=\":AB:\" />")
        // A code longer than the trie takes (64 scalars) is left out: a position's walk is bounded whatever the table.
        let longCode = String(repeating: "a", count: 65), longestCode = String(repeating: "b", count: 64)
        let long = HFRBBCodeWriter(smileysEnabled: true, smileys: [longCode: url, longestCode: url])
        #expect(long.html(for: longCode) == "<p>" + longCode)
        #expect(long.html(for: longestCode).contains("<img"))
        let dOnly = HFRBBCodeWriter(smileysEnabled: true, smileys: [":D": url])
        #expect(dOnly.html(for: ":d") == "<p><img src=\"https://forum-images.hardware.fr/icones/biggrin.gif\" alt=\":d\" title=\":D\" />")
    }

    @Test("Escaping: the four characters HFR escapes, and nothing else, once in text; a quote twice in a URL attribute (R95d, R443f)")
    func escaping() {
        #expect(Self.html("plain <b>html</b> & \"quotes\" 'x'") == "<p>plain &lt;b&gt;html&lt;/b&gt; &amp; &#034;quotes&#034; 'x'")
        #expect(Self.html("a\u{FFFF}b\u{FFFE}c" + String(HFRBBCodeWriter.noBreakSpaceMarker) + "d") == "<p>abcd")
        #expect(Self.html("\u{FFFF}0\u{FFFF} [url]https://a.example/[/url]")
            == "<p>0 <a href=\"https://a.example/\" class=\"cLink\">https://a.example/</a>")
        #expect(Self.html("[url=https://a.example/?a=1&b=\"]x & \"y\"[/url]")
            == "<p><a href=\"https://a.example/?a=1&amp;b=&amp;#034;\" class=\"cLink\">x &amp; &#034;y&#034;</a>")
    }

    /// The adversarial shapes, each a function of a repeat count: nesting, unclosed tags and colours, rejected URL
    /// arguments, bullets, glued smileys and prose, a `[:perso` wall, stray colour closes.
    static func shapes(_ count: Int) -> [String] {
        [
            String(repeating: "[b]", count: count * 2) + "x" + String(repeating: "[/b]", count: count * 2),
            String(repeating: "[quote]", count: count) + "y" + String(repeating: "[/quote]", count: count),
            "[quote]" + String(repeating: "[/quote]", count: count),
            String(repeating: "[b][i][quote][url=https://a.example/][#ff0000][img]", count: count / 4) + "z",
            String(repeating: "[url]\n", count: count) + "[/url]",
            String(repeating: "[url=a]x", count: count),
            (0..<count).map { String(format: "[#%06x]x", $0) }.joined(),
            String(repeating: "[url]x[/url][img][/img][#ff0000]a[/#00ff00]", count: count / 2) + "[/url]",
            String(repeating: "[*]a\n", count: count * 2),
            String(repeating: ":D :) [:user] ", count: count),
            String(repeating: ":)", count: count * 2),
            "https://x/" + String(repeating: ":)", count: count * 2),
            String(repeating: "[url=", count: count) + "]x[/url]",
            String(repeating: "[img][", count: count) + "[/img]",
            String(repeating: "Bonjour à tous, voici ma pizza :) et mon four :D !\r\n", count: count / 8),
            String(repeating: "[:perso", count: count),
            String(repeating: "[/#000000]", count: count) + "[#000000]x",
            String(repeating: "[u][b]x[/u][/b]\r\n", count: count),
            String(repeating: "[fixed]", count: count) + "[code]x[/code][/fixed]"
        ]
    }

    @Test("Every pass is one scan: each 32-172 KB shape costs about 4x more at 4x the size (asserted under 6x plus half a second)")
    func linearWork() throws {
        // The bundled catalogue (59 codes) plus a thousand personal smileys: the trie walk costs the longest code,
        // not the table.
        var smileys = try Dictionary(CommonSmileyCatalog.bundled().map { ($0.code, $0.url) }, uniquingKeysWith: { first, _ in first })
        let perso = try #require(URL(string: "https://forum-images.hardware.fr/images/perso/user.gif"))
        for number in 0..<1_000 { smileys["[:user\(number)]"] = perso }
        let writer = HFRBBCodeWriter(smileysEnabled: true, smileys: smileys)
        /// The faster of two runs, so a stall of the runner during one of them does not count.
        func time(_ source: String) -> (Duration, String) {
            var best = Duration.seconds(1_000), html = ""
            for _ in 0..<2 {
                let start = ContinuousClock.now
                html = writer.html(for: source)
                best = min(best, ContinuousClock.now - start)
            }
            return (best, html)
        }
        for (small, large) in zip(Self.shapes(2_000), Self.shapes(8_000)) {
            let (smallTime, smallHTML) = time(small), (largeTime, largeHTML) = time(large)
            // The output holds every scalar of the source (text or markup) and no marker.
            #expect(largeHTML.unicodeScalars.count >= large.unicodeScalars.count)
            #expect(smallHTML.unicodeScalars.count >= small.unicodeScalars.count)
            #expect(!largeHTML.unicodeScalars.contains { $0 == "\u{FFFF}" || $0 == "\u{FFFE}" || $0 == HFRBBCodeWriter.noBreakSpaceMarker })
            // Four times the size, at most about four times the time (a quadratic pass gives sixteen); the half second
            // absorbs the noise of the small runs. Measured on debug builds: tens to hundreds of ms per shape at 8 000.
            #expect(largeTime < smallTime * 6 + .milliseconds(500), "\(large.prefix(30)): \(smallTime) → \(largeTime)")
        }
    }

    @Test("Passes work on scalars: a combining mark after a quote, a bracket or a marker hides nothing")
    func combiningMarks() {
        let mark = "\u{301}"
        #expect(Self.html("a\"\(mark)b &\(mark)c <\(mark)d >\(mark)e") == "<p>a&#034;\(mark)b &amp;\(mark)c &lt;\(mark)d &gt;\(mark)e")
        #expect(Self.html("[url=https://a.example/\"\(mark) class=spoiler title=injected]t[/url]")
            == "<p><a href=\"https://a.example/&amp;#034;\(mark) class=spoiler title=injected\" class=\"cLink\">t</a>")
        #expect(Self.html("[img]https://a.example/i.png\"\(mark) class=x[/img]")
            == "<p><img src=\"https://a.example/i.png&amp;#034;\(mark) class=x\" alt=\"https://a.example/i.png&amp;#034;\(mark) class=x\""
            + " title=\"https://a.example/i.png&amp;#034;\(mark) class=x\" />")
        #expect(Self.html("[b]x[/b]\(mark)") == "<p><strong>x</strong>\(mark)")
        #expect(Self.html("[quote]a[/quote]\u{FE0F}").hasPrefix("<p></p><div class=\"container\">"))
        #expect(Self.html("x[url=https://a/]t[/url]\(mark)y[url=https://b/]u[/url]")
            == "<p>x<a href=\"https://a/\" class=\"cLink\">t</a>\(mark)y<a href=\"https://b/\" class=\"cLink\">u</a>")
        #expect(Self.html("\u{FFFF}\(mark)0\u{FFFF}") == "<p>\(mark)0")
        #expect(Self.html("[#\u{FF26}\u{FF26}0000]x[/#\u{FF26}\u{FF26}0000]") == "<p>[#\u{FF26}\u{FF26}0000]x[/#\u{FF26}\u{FF26}0000]")
    }

    @Test("Placeholders cannot be steered or nested by the text: digits next to a marker, a raw block inside a URL")
    func placeholders() throws {
        let url = try #require(URL(string: "https://forum-images.hardware.fr/icones/redface.gif"))
        let writer = HFRBBCodeWriter(smileysEnabled: true, smileys: [":o": url])
        #expect(writer.html(for: "\u{600}:o 5 :o")
            == "<p>\u{600}<img src=\"https://forum-images.hardware.fr/icones/redface.gif\" alt=\":o\" title=\":o\" /> 5 "
            + "<img src=\"https://forum-images.hardware.fr/icones/redface.gif\" alt=\":o\" title=\":o\" />")
        #expect(writer.html(for: "x\u{600}:o0[url]https://a.example/[/url]")
            == "<p>x\u{600}<img src=\"https://forum-images.hardware.fr/icones/redface.gif\" alt=\":o\" title=\":o\" />0"
            + "<a href=\"https://a.example/\" class=\"cLink\">https://a.example/</a>")
        #expect(Self.html("[url][code]x[/code][/url]")
            == "<p>[url]</p><table class=\"code\"><tr class=\"none\"><td><b class=\"s1\">Code :</b>"
            + "<br /><ol class=\"olcode\"><li>x</li></ol></td></tr></table><p>[/url]")
        #expect(Self.html("[url=[code]x[/code]]t[/url]").hasPrefix("<p>[url=</p><table class=\"code\">"))
        #expect(Self.html("[img][fixed]x[/fixed][/img]").hasSuffix("</td></tr></table><p>[/img]"))
        #expect(!Self.html("[url][fixed]x[/fixed][/url] \u{FFFF}1\u{FFFF}").contains("\u{FFFF}"))
        // A raw block inside a raw block: a `[fixed]` around a block loses its tags (R443n), nothing leaks.
        let nested = Self.html("[fixed]a [cpp]int x;[/cpp] b[/fixed] end")
        #expect(nested == "<p>a </p><table class=\"code\"><tr class=\"none\"><td><b class=\"s1\">Code :</b><br />"
            + "<ol class=\"olcode\"><li><span style=\"color:blue\">int</span> x;</li></ol></td></tr></table><p> b end")
        #expect(!Self.html("[code]a[cpp]x[/cpp]b[/code]").contains("\u{FFFF}"))
        #expect(!Self.html("[fixed][code]x[/code][/fixed]").contains("\u{FFFF}"))
        // A `[code]` in a `[cpp]` is a code table inside the cpp item, its content escaped and coloured again (R443n); a tag
        // inside itself closes at the first close.
        let codeHead = "<p></p><table class=\"code\"><tr class=\"none\"><td><b class=\"s1\">Code :</b><br /><ol class=\"olcode\">"
        #expect(Self.html("[cpp]c [code]int y;[/code] c[/cpp]") == codeHead + "<li>c </p><table class=\"code\"><tr class=\"none\"><td>"
            + "<b class=\"s1\">Code :</b><br /><ol class=\"olcode\"><li>&lt;span style=&#034;color:blue&#034;&gt;"
            + "<span style=\"color:blue\">int</span>&lt;/span&gt; y;</li></ol></td></tr></table><p> c</li></ol></td></tr></table><p>")
        #expect(Self.html("[code]c [fixed]z[/fixed] c[/code]") == codeHead + "<li>c </p><table class=\"fixed\"><tr class=\"none\"><td>"
            + "<p>z</p></td></tr></table><p> c</li></ol></td></tr></table><p>")
        #expect(Self.html("[code][code]x[/code][/code]") == codeHead + "<li>[code]x</li></ol></td></tr></table><p>[/code]")
        // A code made of digits never rewrites a held fragment.
        let digits = HFRBBCodeWriter(smileysEnabled: true, smileys: ["0": try #require(URL(string: "https://a.example/0.gif"))])
        #expect(digits.html(for: "[url]https://a.example/[/url] 0")
            == "<p><a href=\"https://a.example/\" class=\"cLink\">https://a.example/</a> "
            + "<img src=\"https://a.example/0.gif\" alt=\"0\" title=\"0\" />")
    }

    @Test("A bullet consumes its own line break, never a break the writer wrote in a block header")
    func bulletWithBlock() {
        #expect(Self.html("[*]item [quote]q[/quote] after\r\nnext")
            == "<p></p><ul><li>item </p><div class=\"container\"><table class=\"quote\"><tr class=\"none\"><td>"
            + "<b class=\"s1\">Citation :</b><br /><br /><p>q<br /></p></td></tr></table></div><p> after\r</li></ul><p>next")
    }
}
