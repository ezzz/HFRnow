import Foundation
import HFRModels
import SwiftSoup
import Testing
@testable import HFRParsing

/// ADR 0014 §4: a member's text never becomes markup, every URL goes through the sanitizer of record, and the work
/// stays bounded whatever the nesting. Inline sources only: no capture is involved, every case is a draft a member
/// could type.
@Suite("BBCode renderer sanitization")
struct BBCodeRendererSanitizationTests {
    @Test(
        "A url tag with a rejected scheme previews as text, never as a link",
        arguments: [
            "javascript:alert(1)", "JaVaScRiPt:alert(1)", "java\tscript:alert(1)", " javascript:alert(1)", "data:text/html,x",
            "file:///etc/passwd", "blob:https://x/y", "vbscript:x", "https://forum.hardware.fr@evil.example/",
            "%6Aavascript:alert(1)", "tel:0123", "mailto:a@b.c"
        ]
    )
    func rejectedLinkSchemes(url: String) throws {
        let named = try BBCodeRenderer.render("see [url=\(url)]here[/url]!")
        #expect(named.html == "<p>see here!</p>")
        #expect(named.links.isEmpty)
        let bare = try BBCodeRenderer.render("[url]\(url)[/url]")
        #expect(bare.links.isEmpty)
        #expect(!bare.html.contains("<a"))
        #expect(try Self.text(of: bare.html) == url.trimmingCharacters(in: [" "]))
    }

    @Test("A line break inside a tag's brackets makes it text, so a split scheme never reaches a URL")
    func splitTagIsText() throws {
        let content = try BBCodeRenderer.render("[url=java\nscript:alert(1)]here[/url]")
        #expect(content.links.isEmpty)
        #expect(content.html == "<p>[url=java\r<br />script:alert(1)]here[/url]</p>")
    }

    @Test(
        "An img tag with a rejected scheme previews as nothing, never as an image",
        arguments: ["javascript:alert(1)", "data:image/png;base64,AAAA", "file:///x.png", "blob:https://x/y", "//", " "]
    )
    func rejectedImageSchemes(url: String) throws {
        let content = try BBCodeRenderer.render("a[img]\(url)[/img]b")
        #expect(content.html == "<p>ab</p>")
        #expect(content.images.isEmpty && content.smileys.isEmpty)
    }

    @Test("Raw HTML, handlers and entities in the text stay text (R95d: HFR escapes them too)")
    func rawHTMLIsText() throws {
        let source = "plain <b>html</b> & \"quotes\" <img src=x onerror=alert(1)> &lt;i&gt; <script>x</script>"
        let content = try BBCodeRenderer.render(source)
        #expect(content.html == "<p>plain &lt;b&gt;html&lt;/b&gt; &amp; \"quotes\" &lt;img src=x onerror=alert(1)&gt; "
            + "&amp;lt;i&amp;gt; &lt;script&gt;x&lt;/script&gt;</p>")
        #expect(try Self.text(of: content.html) == source)
        #expect(content.images.isEmpty && content.links.isEmpty)
    }

    @Test("A url argument or an img URL holding quotes or brackets is an attribute value, never markup")
    func attributeInjection() throws {
        let content = try BBCodeRenderer.render("[url=https://a.example/x\"onclick=\"alert(1)]t[/url]")
        // The quotes are percent-encoded inside the one `href` value: no second attribute appears.
        #expect(content.html == "<p><a href=\"https://a.example/x%22onclick=%22alert(1)\" class=\"cLink\">t</a></p>")
        #expect(content.links.map(\.url.absoluteString) == ["https://a.example/x%22onclick=%22alert(1)"])
        // A combining mark after the quote does not hide it from the escaping (scalar-based passes).
        let marked = try BBCodeRenderer.render("[url=https://a.example/\"\u{301} class=spoiler title=injected]t[/url]")
        // The whole argument stays one `href` value (percent-encoded); no `title` or `class` attribute of the member's.
        #expect(!marked.html.contains(" title=\"") && !marked.html.contains(" class=\"spoiler\""))
        #expect(marked.links.map(\.url.absoluteString) == ["https://a.example/%22%CC%81%20class=spoiler%20title=injected"])
        let markedImage = try BBCodeRenderer.render("[img]https://a.example/i.png\"\u{301} class=smileycustom title=injected[/img]")
        #expect(!markedImage.html.contains("title=\"injected\"") && !markedImage.html.contains(" class=\"smileycustom\""))
        #expect(markedImage.smileys.isEmpty && markedImage.images.count == 1)
        let image = try BBCodeRenderer.render("[img]https://a.example/i.png\"><script>x</script>[/img]")
        #expect(!image.html.contains("<script"))
        #expect(image.images.count <= 1)
    }

    @Test("An accepted url or img keeps the sanitizer's rules: absolute, https on the forum, hfr-rehost.net as reho.st")
    func acceptedURLs() throws {
        let content = try BBCodeRenderer.render(
            "[url=http://forum.hardware.fr/hfr/x.htm]a[/url] [url]example.org/y[/url] [img]http://hfr-rehost.net/self/a.jpg[/img]"
        )
        #expect(content.links.map(\.url.absoluteString) == ["https://forum.hardware.fr/hfr/x.htm", "http://example.org/y"])
        #expect(content.images.map(\.url.absoluteString) == ["http://reho.st/self/a.jpg"])
        #expect(content.html.contains("<img src=\"http://reho.st/self/a.jpg\" alt=\"http://hfr-rehost.net/self/a.jpg\""))
    }

    @Test("A smiley-path image is a smiley of the typed lists, as for a posted message (R95d: jap.gif)")
    func smileyPathImage() throws {
        let content = try BBCodeRenderer.render("[img]https://forum-images.hardware.fr/icones/smilies/jap.gif[/img]")
        #expect(content.images.isEmpty)
        #expect(content.smileys.map(\.kind) == [.standard])
    }

    @Test("10 000 nested or unclosed tags render on a cooperative-pool thread (512 KB stack)")
    func deepNesting() async throws {
        let depth = 10_000
        // Non-greedy pairs: the first `[b]` closes at the first `[/b]`, the rest is text (HFR's nesting of one tag is
        // pending capture); 1 000 nested quotes are written inside out; 10 000 opens without a close are text.
        let bold = String(repeating: "[b]", count: depth) + "x" + String(repeating: "[/b]", count: depth)
        let quotes = String(repeating: "[quote]", count: depth / 10) + "y" + String(repeating: "[/quote]", count: depth / 10)
        let unclosed = String(repeating: "[b][i][quote][url=https://a.example/]", count: depth / 4) + "z"
        // No wall-clock bound: the suite runs in parallel and a bound was flaky at 12 s alone, 51 s under load.
        // Linearity holds by construction (every pass is one scan); the three renders complete here instead of hanging.
        let (boldContent, quoteContent, unclosedContent) = try await Task.detached {
            (try BBCodeRenderer.render(bold), try BBCodeRenderer.render(quotes), try BBCodeRenderer.render(unclosed))
        }.value
        #expect(boldContent.html.hasPrefix("<p><strong>[b][b]"))
        #expect(try Self.text(of: boldContent.html).contains("x"))
        #expect(try Self.text(of: quoteContent.html).contains("y"))
        #expect(quoteContent.html.matches(of: /Citation :/).count == depth / 10)
        #expect(try Self.text(of: unclosedContent.html) == unclosed)
        #expect(unclosedContent.links.isEmpty)
    }

    /// The visible text of normalized HTML.
    static func text(of html: String) throws -> String {
        try SwiftSoup.parseBodyFragment(html).body()?.text(trimAndNormaliseWhitespace: false) ?? ""
    }
}
