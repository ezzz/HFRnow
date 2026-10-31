import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// LOT-035: legacy's four video patterns as unit cases (`ParseMessagesOperation.m:241-244`), the start time, the candidate
/// rule on small content fragments, and the one captured link with a start (`R28`). The differential test against every
/// LOT-003 oracle is in `MessageContentOracleTests`.
@Suite("Video embed detector")
struct MessageEmbedDetectorTests {
    private static func embed(_ link: String) throws -> MessageEmbed? {
        MessageEmbedDetector.embed(for: try #require(URL(string: link)))
    }

    @Test(
        "Each legacy video host gives its player, built from the id",
        arguments: [
            ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", EmbedProvider.youtube, "https://www.youtube.com/embed/dQw4w9WgXcQ"),
            ("http://youtube.com/watch?v=dQw4w9WgXcQ", .youtube, "https://www.youtube.com/embed/dQw4w9WgXcQ"),
            ("https://m.youtube.com/watch?feature=share&v=a-b_c", .youtube, "https://www.youtube.com/embed/a-b_c"),
            ("https://gaming.youtube.com/watch?v=abc123", .youtube, "https://www.youtube.com/embed/abc123"),
            ("https://youtu.be/dQw4w9WgXcQ", .youtube, "https://www.youtube.com/embed/dQw4w9WgXcQ"),
            ("https://vimeo.com/123456", .vimeo, "https://player.vimeo.com/video/123456"),
            ("https://vimeo.com/channels/staffpicks/123456", .vimeo, "https://player.vimeo.com/video/123456"),
            ("https://streamable.com/abc12", .streamable, "https://streamable.com/s/abc12")
        ]
    )
    func hosts(link: String, provider: EmbedProvider, player: String) throws {
        let embed = try #require(try Self.embed(link))
        #expect(embed.provider == provider)
        #expect(embed.embedURL.absoluteString == player)
        #expect(embed.sourceURL.absoluteString == link)
    }

    @Test(
        "Other hosts and look-alikes stay links",
        arguments: [
            "https://www.dailymotion.com/video/x7tgad0", "https://coub.com/view/1a2b", "https://www.twitch.tv/somechannel",
            "http://streamable.com/abc12", "https://vimeo.com/user/abc", "https://youtube.com.example.org/watch?v=abc",
            "https://youtubeXcom/watch?v=abc", "https://youtuXbe/abc", "https://example.org/?u=https://youtu.be/abc",
            "https://www.youtube.com/watch", "https://youtu.be/"
        ]
    )
    func notVideos(link: String) throws {
        #expect(try Self.embed(link) == nil)
    }

    @Test(
        "The start comes from `t`: plain seconds or h/m/s, hours counted as hours (legacy: minutes × 3600)",
        arguments: [
            ("https://youtu.be/abc?t=1h2m3s", 3723), ("https://www.youtube.com/watch?v=abc&t=2m", 120),
            ("https://youtu.be/abc?t=45s", 45), ("https://youtu.be/abc?t=706", 706), ("https://youtu.be/abc?t=1h", 3600),
            ("https://youtu.be/abc?t=1h2m3s&feature=share", 3723), ("https://youtu.be/abc?t=10&t=20", 20)
        ]
    )
    func start(link: String, seconds: Int) throws {
        let embed = try #require(try Self.embed(link))
        #expect(embed.startSeconds == seconds)
        #expect(embed.embedURL.absoluteString == "https://www.youtube.com/embed/abc?start=\(seconds)")
    }

    @Test(
        "No start without a usable `t`",
        arguments: ["https://youtu.be/abc", "https://youtu.be/abc?t=0", "https://youtu.be/abc?t=", "https://youtu.be/abc?t=abc",
                    "https://youtu.be/abc?t=1m2h", "https://youtu.be/abc?start=30", "https://youtu.be/abc?t=9999999"]
    )
    func noStart(link: String) throws {
        let embed = try #require(try Self.embed(link))
        #expect(embed.startSeconds == nil)
        #expect(embed.embedURL.absoluteString == "https://www.youtube.com/embed/abc")
    }

    @Test("Vimeo and Streamable links get no start, as in legacy")
    func startOnlyOnYouTube() throws {
        #expect(try Self.embed("https://vimeo.com/123456?t=30")?.startSeconds == nil)
        #expect(try Self.embed("https://streamable.com/abc12?t=30")?.startSeconds == nil)
    }

    @Test("R28: the captured `youtu.be/…?t=706` link plays from 706 s (legacy embedded it without a start)")
    func capturedStart() throws {
        let page = try Fixture.capture("R28-topic-images-videos-anon")
        let block = try #require(try MessageBlockParser.blocks(in: page).first { $0.numreponse == 75482040 })
        let content = try MessageContentNormalizer.normalize(contentHTML: block.contentHTML)
        let embed = try #require(content.embeds.first)
        #expect(content.embeds.count == 1)
        #expect(embed.sourceURL.absoluteString == "https://youtu.be/L_2ggcnsMog?t=706")
        #expect(embed.embedURL.absoluteString == "https://www.youtube.com/embed/L_2ggcnsMog?start=706")
        #expect(embed.startSeconds == 706)
    }

    // MARK: - Candidates (small content fragments: no page state, the structure the rule reads)

    private static let video = "https://youtu.be/abc"

    private static func embeds(inContent html: String) throws -> [MessageEmbed] {
        try MessageContentNormalizer.normalize(contentHTML: html).embeds
    }

    @Test("A text-only `cLink` in a top-level paragraph is a candidate; elsewhere it stays a link")
    func candidates() throws {
        let link = "<a href=\"\(Self.video)\" class=\"cLink\">\(Self.video)</a>"
        #expect(try Self.embeds(inContent: "<p>\(link)</p>").count == 1)
        #expect(try Self.embeds(inContent: "<p><strong>\(link)</strong></p>").isEmpty)
        #expect(try Self.embeds(inContent: "<p><a href=\"\(Self.video)\">\(Self.video)</a></p>").isEmpty)
        #expect(try Self.embeds(inContent: "<p><a href=\"\(Self.video)\" class=\"cLink\"><strong>vidéo</strong></a></p>").isEmpty)
        let quoted = "<div class=\"container\"><table class=\"citation\"><tr class=\"none\"><td><p>\(link)</p></td></tr></table></div>"
        #expect(try Self.embeds(inContent: quoted).isEmpty)
        #expect(try Self.embeds(inContent: "<p>texte</p><span class=\"signature\"><p>\(link)</p></span>").isEmpty)
    }

    @Test("The corpus has embeds to compare: the LOT-003 oracles hold 16 iframes over 8 pages")
    func corpusHasEmbeds() throws {
        var total = 0
        for caseID in MessageContentOracleTests.cases {
            let map = try TopicOracle.loadMap()
            let blocks = try MessageBlockParser.blocks(in: TopicOracle.capture(for: try #require(map[caseID])))
            total += try blocks.reduce(0) { $0 + (try MessageContentNormalizer.normalize(contentHTML: $1.contentHTML)).embeds.count }
        }
        #expect(total >= 16)
    }
}
