import Foundation
import HFRModels
import SwiftSoup
import Testing
@testable import HFRParsing

/// Differential tests (ADR 0004): every message of the 20 LOT-003 topic oracles against `MessageContentNormalizer`.
/// The oracle is the legacy `toHTML:isMP:` output (`result.messages[].html`, `display_sig=no`, `display_images=yes`),
/// reduced to its `div#para…` element minus the `div.edited` trailer. Bytes are never compared (libxml2 serialization,
/// regex rewrites): the visible text and the typed values are (`docs/lots/LOT-034-content-normalization.md`, "Oracle coverage").
@Suite("Message content vs LOT-003 oracle")
struct MessageContentOracleTests {
    static let cases = MessageBlockOracleTests.cases

    @Test("Text, smileys, images and links equal the legacy rewrite", arguments: cases)
    func matchesOracle(caseID: String) throws {
        let map = try TopicOracle.loadMap()
        let entry = try #require(map[caseID])
        let oracle = try TopicOracle.load(caseID)
        let blocks = try MessageBlockParser.blocks(in: TopicOracle.capture(for: entry))
        try #require(blocks.count == oracle.result.messages.count, "\(caseID): block count")

        for (block, expected) in zip(blocks, oracle.result.messages) {
            let label = "\(caseID) message \(expected.index)"
            let content = try MessageContentNormalizer.normalize(contentHTML: block.contentHTML)
            let legacy = try LegacyContent(html: #require(expected.html, "\(label): html"))
            // The oracle ran with `embedded_videos=yes`: legacy replaced the video links it recognized by an iframe, text
            // included (LOT-035 territory). Those links are set aside here and counted against the oracle's iframes.
            let embedded = try Self.linksLegacyEmbedded(in: content.html)
            try #require(embedded.count == legacy.embeds, "\(label): links legacy turned into iframes")

            #expect(Self.compact(try Self.text(of: content.html, excluding: embedded)) == legacy.text, "\(label): visible text")
            #expect(content.images.map(Self.imageKey) == legacy.images, "\(label): images")
            #expect(content.smileys.filter { $0.kind == .custom }.map(Self.smileyKey) == legacy.customSmileys, "\(label): custom smileys")
            #expect(
                content.smileys.filter { $0.kind == .standard }.map(Self.smileyKey) == legacy.standardSmileys, "\(label): standard smileys"
            )
            let links = content.links.filter { !embedded.contains($0.url) }.map(Self.linkKey)
            #expect(links == legacy.links, "\(label): links")
            #expect((content.signatureHTML != nil) == block.contentHTML.contains("<span class=\"signature\">"), "\(label): signature")
            #expect(content.embeds.isEmpty, "\(label): embeds are LOT-035")
            for html in [content.html, content.signatureHTML ?? ""] {
                #expect(!html.contains("javascript:") && !html.contains("<script") && !html.contains(" id="), "\(label): sanitized")
                #expect(html.firstMatch(of: /\son[a-z]+=/) == nil, "\(label): no event handler")
            }
        }
    }

    @Test("The corpus totals of LOT-003 RC3.9 are reproduced, so the comparison is not vacuous")
    func corpusTotals() throws {
        let map = try TopicOracle.loadMap()
        var signatures = 0, withCustomSmileys = 0, withImages = 0, links = 0
        for caseID in Self.cases {
            let entry = try #require(map[caseID])
            for block in try MessageBlockParser.blocks(in: TopicOracle.capture(for: entry)) {
                let content = try MessageContentNormalizer.normalize(contentHTML: block.contentHTML)
                signatures += content.signatureHTML == nil ? 0 : 1
                withCustomSmileys += content.smileys.contains { $0.kind == .custom } ? 1 : 0
                withImages += content.images.isEmpty ? 0 : 1
                links += content.links.count
            }
        }
        #expect(signatures == 125)
        #expect(withCustomSmileys == 103)
        #expect(withImages == 36)
        #expect(links > 300, "the corpus holds hundreds of links (\(links))")
    }

    // MARK: - Keys compared on both sides

    static func imageKey(_ image: MessageImage) -> String {
        "\(Self.urlKey(image.url))|\(image.linkURL.map(Self.urlKey) ?? "")"
    }

    static func smileyKey(_ smiley: MessageSmiley) -> String {
        "\(Self.urlKey(smiley.url))|\(smiley.code)"
    }

    static func linkKey(_ link: MessageLink) -> String {
        "\(Self.urlKey(link.url))|\(Self.compact(link.text))"
    }

    /// libxml2 percent-encodes the spaces of an attribute when serializing, our URLs are built from the raw value.
    static func urlKey(_ url: URL) -> String {
        url.absoluteString.removingPercentEncoding ?? url.absoluteString
    }

    /// Legacy deleted every `\n` of the content (audit C quirk 2) and libxml2 wrote U+00A0 raw: compare without whitespace.
    static func compact(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    /// Visible text of a fragment, the links whose URL is in `excluding` removed first.
    static func text(of html: String, excluding: [URL] = []) throws -> String {
        guard let body = try SwiftSoup.parseBodyFragment(html).body() else { return "" }
        for link in try body.select("a[href]") where excluding.contains(try #require(URL(string: try link.attr("href")))) {
            try link.remove()
        }
        return try body.text()
    }

    /// The links of a normalized body that legacy turned into iframes (`ParseMessagesOperation.m:241-244, 260-264`,
    /// `LinkItem.m:149`): `a.cLink` two levels under the content element, text-only, on one of the four video hosts.
    static func linksLegacyEmbedded(in html: String) throws -> [URL] {
        guard let body = try SwiftSoup.parseBodyFragment(html).body() else { return [] }
        var embedded: [URL] = []
        for link in try body.select("a.cLink") where link.parent()?.parent() === body && link.children().isEmpty {
            let href = try link.attr("href")
            guard legacyVideoPatterns.contains(where: { href.firstMatch(of: $0) != nil }) else { continue }
            embedded.append(try #require(URL(string: href)))
        }
        return embedded
    }

    nonisolated(unsafe) static let legacyVideoPatterns = [
        /^http(?:s)?:\/\/(?:www.|m.|gaming.)?(youtu)be.com\/.+v=([\w-]+)\/?/,
        /^http(?:s)?:\/\/(youtu).be\/([\w-]+)\/?/,
        /^http(?:s)?:\/\/(vimeo).com\/(?:[a-zA-Z]+\/)*([0-9]+)/,
        /^https:\/\/(streamable).com\/([\w]+)\/?/
    ]

    /// The legacy content of one message, read back from the filled template.
    struct LegacyContent {
        var text: String
        var images: [String] = []
        var customSmileys: [String] = []
        var standardSmileys: [String] = []
        var links: [String] = []
        /// Video links legacy replaced by an iframe (`div.embedvideo`).
        var embeds = 0

        init(html: String) throws {
            let document = try SwiftSoup.parseBodyFragment(html)
            let content = try #require(try document.select("div[id^=para]").first(), "oracle content element")
            try content.select("div.edited").remove()
            embeds = try content.select("div.embedvideo").count
            text = MessageContentOracleTests.compact(try content.text())
            for element in try content.getAllElements().array().dropFirst() {
                switch element.tagName() {
                case "img":
                    try readImage(element)
                case "a" where !(try Self.wrapsLegacyImage(element)):
                    // Legacy fixed only the `/forum2.php` and `/hfr/` prefixes; the same resolver on both sides compares the rest.
                    guard let url = MessageContentNormalizer.normalizedURL(try element.attr("href"), relativeTo: HFRURL.base) else {
                        continue
                    }
                    links.append("\(MessageContentOracleTests.urlKey(url))|\(MessageContentOracleTests.compact(try element.text()))")
                default:
                    break
                }
            }
        }

        private mutating func readImage(_ image: Element) throws {
            let classes = try image.classNames()
            let source = try #require(HFRURL.absolute(try image.attr("src")), "oracle image URL")
            if classes.contains(MessageContentNormalizer.customSmileyClass) {
                // `onClick="window.location = 'oijlkajsdoihjlkjasdosmiley://smileycode/<code>/'+…"`, `'` escaped as `\'`.
                let onClick = try image.attr("onClick")
                let code = try #require(onClick.firstMatch(of: /smileycode\/(.*?)\/'\+encodeURIComponent/)?.output.1, "smiley code")
                customSmileys.append("\(MessageContentOracleTests.urlKey(source))|[:\(code.replacing("\\'", with: "'"))]")
            } else if classes.contains(MessageContentNormalizer.imageClass) {
                let link = try image.attr("longdesc")
                let linkKey = link.isEmpty ? "" : MessageContentOracleTests.urlKey(try #require(HFRURL.absolute(link), "longdesc"))
                images.append("\(MessageContentOracleTests.urlKey(source))|\(linkKey)")
            } else {
                standardSmileys.append("\(MessageContentOracleTests.urlKey(source))|\(try image.attr("alt"))")
            }
        }

        /// Legacy wraps every image, bare or linked, in a link (`LinkItem.m:173, 178`): that link is the image's, not a link.
        private static func wrapsLegacyImage(_ link: Element) throws -> Bool {
            let children = link.children()
            guard children.count == 1, let image = children.first, image.tagName() == "img" else { return false }
            return try image.classNames().contains(MessageContentNormalizer.imageClass) && link.ownRawText.allSatisfy(\.isWhitespace)
        }
    }
}
