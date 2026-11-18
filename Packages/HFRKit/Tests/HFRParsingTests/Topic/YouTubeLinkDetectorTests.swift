import Foundation
import Testing
@testable import HFRParsing

/// #1037: plain YouTube video links of a message (thumbnail cards in the reader). The LOT-035 embed rule is tested in
/// `MessageEmbedDetectorTests`; here only what the cards add: the accepted URL forms, the exclusions and the candidate rule.
@Suite("YouTube link detector")
struct YouTubeLinkDetectorTests {
    private static func video(_ link: String) throws -> YouTubeVideoLink? {
        YouTubeLinkDetector.video(for: try #require(URL(string: link)))
    }

    @Test(
        "Each video URL form gives its id, start time and the thumbnail URL",
        arguments: [
            ("https://youtu.be/dQw4w9WgXcQ", "dQw4w9WgXcQ", nil as Int?),
            ("https://youtu.be/dQw4w9WgXcQ?t=90", "dQw4w9WgXcQ", 90),
            ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ", nil),
            ("https://youtube.com/watch?v=dQw4w9WgXcQ&t=1m5s", "dQw4w9WgXcQ", 65),
            ("https://m.youtube.com/watch?feature=share&v=a-b_c", "a-b_c", nil),
            ("https://www.youtube.com/watch?list=PL1&v=abc123&t=706", "abc123", 706),
            ("https://www.youtube.com/shorts/Ab_-12345xy", "Ab_-12345xy", nil),
            ("https://m.youtube.com/shorts/abc123", "abc123", nil),
            ("http://youtu.be/abc123", "abc123", nil),
            ("https://YOUTU.BE/abc123", "abc123", nil),
            ("https://WWW.YouTube.com/watch?v=abc123", "abc123", nil)
        ]
    )
    func forms(link: String, id: String, start: Int?) throws {
        let video = try #require(try Self.video(link))
        #expect(video.videoID == id)
        #expect(video.startSeconds == start)
        #expect(video.thumbnailURL.absoluteString == "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
        #expect(video.sourceURL.absoluteString == link)
    }

    @Test("A video link is opened over https, whatever the posted scheme")
    func openURLIsHTTPS() throws {
        let video = try #require(try Self.video("http://youtu.be/abc123?t=5"))
        #expect(video.openURL.absoluteString == "https://youtu.be/abc123?t=5")
        let already = try #require(try Self.video("https://youtu.be/abc123"))
        #expect(already.openURL == already.sourceURL)
    }

    @Test(
        "A channel, a playlist, a look-alike or an unsafe id is no video",
        arguments: [
            "https://www.youtube.com/channel/UCabcdef", "https://www.youtube.com/@somechannel", "https://www.youtube.com/playlist?list=PL1",
            "https://www.youtube.com/user/someone", "https://www.youtube.com/watch", "https://www.youtube.com/watch?v=",
            "https://www.youtube.com/watch?v=a%20b", "https://www.youtube.com/watch?notv=abc", "https://www.youtube.com/results?v=abc",
            "https://www.youtube.com/embed/abc123", "https://www.youtube.com/shorts/", "https://www.youtube.com/shorts/a%20b",
            "https://youtu.be/", "https://youtu.be/a%20b", "https://youtube.com.example.org/watch?v=abc", "https://youtubeXcom/watch?v=abc",
            "https://example.org/?u=https://youtu.be/abc", "https://example.org/shorts/abc", "https://vimeo.com/123456",
            "ftp://youtu.be/abc123", "https://user@youtu.be/abc123", "https://www.youtube.com/watch?v=%C3%A9t%C3%A9",
            "https://www.youtube.com:8443/watch?v=abc123", "https://youtu.be:8080/abc123", "https://youtu.be/%C3%A9t%C3%A9"
        ]
    )
    func notVideos(link: String) throws {
        #expect(try Self.video(link) == nil)
    }

    private static func cards(_ html: String) throws -> [String] {
        try YouTubeLinkDetector.cards(inNormalizedHTML: html).map(\.videoID)
    }

    private static func link(_ href: String, text: String? = nil, extra: String = "") -> String {
        "<a class=\"cLink\" href=\"\(href)\"\(extra)>\(text ?? href)</a>"
    }

    @Test("A link nested in formatting, or in a list, whose text is the URL gets a card, in page order")
    func nestedPlainLinks() throws {
        let html = "<p><b>\(Self.link("https://youtu.be/aaa"))</b></p><ul><li>\(Self.link("https://www.youtube.com/watch?v=bbb"))</li></ul>"
        #expect(try Self.cards(html) == ["aaa", "bbb"])
    }

    @Test("A named link stays a text link; the URL as its text, with or without the scheme, is a plain one")
    func namedLink() throws {
        let nested = { (inner: String) in "<p><b>\(inner)</b></p>" }
        #expect(try Self.cards(nested(Self.link("https://youtu.be/aaa", text: "ma vidéo"))) == [])
        #expect(try Self.cards(nested(Self.link("https://youtu.be/aaa", text: " https://youtu.be/aaa "))) == ["aaa"])
        #expect(try Self.cards(nested(Self.link("https://youtu.be/aaa", text: "youtu.be/aaa"))) == ["aaa"])
        #expect(try Self.cards(nested(Self.link("https://youtu.be/aaa", text: "https://youtu.be/bbb"))) == [])
    }

    @Test("A link in a quote, a spoiler or a code block gets no card")
    func tablesExcluded() throws {
        let inTable = "<table class=\"citation\"><tr><td><b>\(Self.link("https://youtu.be/aaa"))</b></td></tr></table>"
        let spoiler = "<table class=\"spoiler\"><tr><td><b>\(Self.link("https://youtu.be/bbb"))</b></td></tr></table>"
        #expect(try Self.cards(inTable + spoiler) == [])
    }

    @Test("A top-level link that LOT-035 turns into a player keeps its placeholder: no card for it")
    func embedsExcluded() throws {
        let html = "<p>\(Self.link("https://youtu.be/aaa"))</p><p><b>\(Self.link("https://youtu.be/bbb"))</b></p>"
        #expect(try YouTubeLinkDetector.cards(inNormalizedHTML: html).map(\.videoID) == ["bbb"])
        // The embed rule itself is untouched: the first one is still the only embed.
        #expect(try MessageEmbedDetector.embeds(inNormalizedHTML: html).map(\.sourceURL.absoluteString) == ["https://youtu.be/aaa"])
    }

    /// Review round 1: a top-level link that LOT-035 does *not* embed (Shorts, an upper-case host: its patterns are case-sensitive and
    /// need a `v=`) has no player either, so it gets the card.
    @Test("A top-level link without a player gets a card")
    func topLevelWithoutPlayer() throws {
        let shorts = "<p>\(Self.link("https://youtube.com/shorts/abc"))</p>"
        let upper = "<p>\(Self.link("https://YOUTU.BE/def"))</p>"
        #expect(try MessageEmbedDetector.embeds(inNormalizedHTML: shorts + upper).isEmpty)
        #expect(try Self.cards(shorts + upper) == ["abc", "def"])
    }

    /// HFR shortens the text of a long auto-link to `<start> [...] <last 10 characters>` (captures `R20`, `R21`, `R27`).
    @Test("A link text shortened by HFR is still the address")
    func shortenedText() throws {
        let href = "https://youtube.com/shorts/abcdefghijk?si=0123456789abcdef"
        let shortened = "https://youtube.com/shorts/abcdefghijk [...] \(href.suffix(10))"
        let nested = { (text: String) in "<p><b>\(Self.link(href, text: text))</b></p>" }
        #expect(try Self.cards(nested(shortened)) == ["abcdefghijk"])
        #expect(try Self.cards(nested("https://youtube.com/shorts/zzzzzzzzzzz [...] \(href.suffix(10))")) == [])
        #expect(try Self.cards(nested("https://youtube.com/shorts/abcdefghijk [...] xxxxxxxxxx")) == [])
        #expect(try Self.cards(nested(" [...] \(href.suffix(10))")) == [])
    }

    /// The card carries the address as posted: the page matches the inline link by it (a `URL` would percent-encode it).
    @Test("The posted address is kept as written")
    func postedAddress() throws {
        let href = "https://youtu.be/aaa?si=é"
        let video = try #require(try YouTubeLinkDetector.cards(inNormalizedHTML: "<p><b>\(Self.link(href))</b></p>").first)
        #expect(video.postedAddress == href)
        #expect(video.sourceURL.absoluteString != href)
    }

    @Test("Other links, channels and links around images or formatted text get no card")
    func otherLinks() throws {
        let html = "<p><b>\(Self.link("https://example.org/page"))\(Self.link("https://www.youtube.com/@chan"))</b></p>"
            + "<p><b><a class=\"cLink\" href=\"https://youtu.be/aaa\"><img src=\"x\"></a></b></p>"
        #expect(try Self.cards(html) == [])
        #expect(try Self.cards("<p>texte sans lien</p>") == [])
    }

    @Test("A second link to the same video gets its own card")
    func repeatedLink() throws {
        let one = "<p><b>\(Self.link("https://youtu.be/aaa"))</b></p>"
        #expect(try Self.cards(one + one) == ["aaa", "aaa"])
    }
}
