import Foundation
import Testing
@testable import HFRParsing

/// The rules of the batch 2 previews (#443, #742) on inline sources, each cited to the capture that shows it; the whole
/// pairs are checked by `BBCodeRendererBatch2OracleTests`.
@Suite("HFR BBCode writer, batch 2 rules")
struct HFRBBCodeWriterBatch2Tests {
    static let writer = HFRBBCodeWriter(smileysEnabled: true, smileys: [:])

    static func html(_ source: String) -> String { writer.html(for: source) }

    @Test("Colour: three or six digits, the first colour close closes whatever its name, the rest stays text (R443c, R443n)")
    func colours() {
        #expect(Self.html("[#f00]a[/#f00] [#FF0000]b[/#FF0000]")
            == "<p><span style=\"color:#f00\">a</span> <span style=\"color:#FF0000\">b</span>")
        #expect(Self.html("[#0055AA]x[/#0055aa]") == "<p><span style=\"color:#0055AA\">x</span>")
        #expect(Self.html("[#ff0000]a [#00ff00]b[/#00ff00] c[/#ff0000]")
            == "<p><span style=\"color:#ff0000\">a [#00ff00]b</span> c[/#ff0000]")
        #expect(Self.html("[#ff00]x[/#ff00] [#ff0000]y") == "<p>[#ff00]x[/#ff00] [#ff0000]y")
    }

    @Test("Bold: [b][/b] is text, a [b] around a block loses its tags, the other tags keep the old rule (R443i, R443j)")
    func bold() {
        #expect(Self.html("[b][/b]") == "<p>[b][/b]")
        #expect(Self.html("[i][/i]") == "<p><em></em>")
        let quote = "</p><div class=\"container\"><table class=\"quote\"><tr class=\"none\">"
            + "<td><b class=\"s1\">Citation :</b><br /><br /><p>x<br />"
            + "</p></td></tr></table></div><p>"
        #expect(Self.html("[b][quote]x[/quote][/b]") == "<p>" + quote)
        #expect(Self.html("[quote][b]x[/quote][/b]") == "<p>" + quote)
    }

    @Test("Quotes: two levels at most, the other opens stay text and the closes pair with the opens that rendered (R443l)")
    func quoteDepth() {
        let html = Self.html("[quote][quote][quote]x[/quote][/quote][/quote]")
        #expect(html.matches(of: /Citation :/).count == 2 && html.contains("<p>[quote]x<br />") && html.hasSuffix("<p>[/quote]"))
        // The spoiler has no captured limit.
        #expect(Self.html("[spoiler][spoiler][spoiler]x[/spoiler][/spoiler][/spoiler]").matches(of: /Spoiler :/).count == 3)
    }

    @Test("A bare http(s) URL is linked up to a smiley or a space, not after [url] nor inside a link text (R443a, R443f)")
    func bareURL() {
        #expect(Self.html("see https://a.example/x.") == "<p>see <a href=\"https://a.example/x.\" class=\"cLink\">https://a.example/x.</a>")
        #expect(Self.html("[url=https://a.example/]see https://b.example/[/url]")
            == "<p><a href=\"https://a.example/\" class=\"cLink\">see https://b.example/</a>")
        #expect(Self.html("ftp://a.example/ www.a.example") == "<p>ftp://a.example/ www.a.example")
    }

    @Test("Smileys and URLs: no protection but the `://`; a `)` after a typed quote or ampersand gets a space (R443a, R443n)")
    func smileysAndURLs() throws {
        let url = try #require(URL(string: "https://forum-images.hardware.fr/icones/biggrin.gif"))
        let smile = try #require(URL(string: "https://forum-images.hardware.fr/icones/smile.gif"))
        let writer = HFRBBCodeWriter(smileysEnabled: true, smileys: [":)": smile])
        // A smiley inside a `[url]` URL is substituted and the tag stays text (R443a).
        #expect(writer.html(for: "[url]https://a.example/:)[/url]")
            == "<p>[url]https://a.example/<img src=\"https://forum-images.hardware.fr/icones/smile.gif\" alt=\":)\" title=\":)\" />[/url]")
        // Codes are matched on the text as typed, never inside the entities of the escaping; a `)` after a typed `"` or `&`
        // gets a space (R443a), so no smiley forms there; a bare URL is linked up to the smiley that ends it (R443a), and the
        // `:/` of `://` is never a smiley.
        let wink = HFRBBCodeWriter(smileysEnabled: true, smileys: [";)": url, ":/": url, ":p": url])
        let biggrin = "<img src=\"https://forum-images.hardware.fr/icones/biggrin.gif\" alt="
        #expect(wink.html(for: "dit \"oui\") & ) et https://a.example/:/x https://a.example/:p ;)")
            == "<p>dit &#034;oui&#034; ) &amp; ) et <a href=\"https://a.example/\" class=\"cLink\">https://a.example/</a>"
            + biggrin + "\":/\" title=\":/\" />x <a href=\"https://a.example/\" class=\"cLink\">https://a.example/</a>"
            + biggrin + "\":p\" title=\":p\" /> " + biggrin + "\";)\" title=\";)\" />")
        #expect(wink.html(for: "oui:p")
            == "<p>oui<img src=\"https://forum-images.hardware.fr/icones/biggrin.gif\" alt=\":p\" title=\":p\" />")
        // A URL gives no protection but its own `://`; a bare URL ends at a quote, a bracket or a smiley.
        #expect(wink.html(for: "voir (http://a.example/:/x) ou [b]https://c.example/:/[/b]")
            == "<p>voir (<a href=\"http://a.example/\" class=\"cLink\">http://a.example/</a>" + biggrin + "\":/\" title=\":/\" />x) ou "
            + "<strong><a href=\"https://c.example/\" class=\"cLink\">https://c.example/</a>" + biggrin + "\":/\" title=\":/\" /></strong>")
    }
}
