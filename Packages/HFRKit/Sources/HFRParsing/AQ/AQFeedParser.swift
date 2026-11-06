import Foundation
import HFRModels
import SwiftSoup

/// Reads the RSS feed of "Alerte Qualitay" (`GET https://aq.super-h.fr/rss.php`, capture `T01`, HFR-PROTOCOL §8).
///
/// Port of `AQRSSParserDelegate` (`AQPlusView.swift:94-245` @ `2440d79`). Each `<item>` has `<title>` (the AQ title), `<link>` (the
/// reported message), `<pubDate>` (RFC 822) and a CDATA HTML `<description>` holding the topic title, the report count and one
/// `<li>` per reporter; legacy read the description with four regular expressions, and so does this port.
public enum AQFeedParser {
    /// Legacy placeholders when the description does not give a topic title or an initiator (`AQPlusView.swift:101, 103`).
    public static let missingTopicTitle = "(sans titre)"
    /// See `missingTopicTitle`.
    public static let missingInitiator = "(sans auteur)"

    /// Items of the feed, in the order served, every category included
    /// (hiding the Apple review category is app policy, Q-7: see `category(of:)`).
    ///
    /// Titles, initiator and comment are entity-decoded (legacy left `&quot;` and `&#039;` in the topic title: bug B4).
    /// An item whose link is not an `https` link to the forum host is skipped (legacy skipped only an empty link,
    /// `AQPlusView.swift:174-180`): the feed comes from a third party and the app follows these links.
    /// - Throws: `missingElement` when the document is not an RSS feed (an HTML error page, an empty body),
    ///   so it cannot read as "no alert".
    public static func parse(_ xml: String) throws(ParsingError) -> [AQFeedItem] {
        let document = try AQXMLDocument.document(from: xml)
        let items: Elements
        do {
            guard try !document.select("rss > channel").isEmpty() else { throw ParsingError.missingElement("rss > channel") }
            items = try document.select("rss > channel > item")
        } catch let error as ParsingError {
            throw error
        } catch {
            throw .malformedDocument
        }
        return items.array().compactMap(item(from:))
    }

    /// Category (`cat` parameter) of an item's link; nil when absent. Legacy hid `&cat=25&post` links by substring
    /// (`AQPlusView.swift:174-180`); callers compare this number with 25 instead.
    public static func category(of item: AQFeedItem) -> Int? {
        HFRURL.queryValue(named: "cat", in: item.link.absoluteString).flatMap(Int.init)
    }

    // MARK: - Implementation

    private static func item(from element: Element) -> AQFeedItem? {
        guard let rawLink = text(of: "link", in: element), let link = HFRURL.absolute(rawLink),
              link.host() == HFRURL.forumHost, link.scheme == "https", link.port == nil else { return nil }
        let description = text(of: "description", in: element) ?? ""
        let details = Details(description: description)
        return AQFeedItem(
            topicTitle: details.topicTitle ?? missingTopicTitle,
            title: text(of: "title", in: element) ?? "",
            comment: details.comment ?? "",
            initiator: details.initiator ?? missingInitiator,
            publishedAt: text(of: "pubDate", in: element).flatMap(RFC822Date.date(from:)),
            link: link
        )
    }

    /// Trimmed text of the first direct child called `name`; nil when absent or empty.
    private static func text(of name: String, in element: Element) -> String? {
        guard let child = element.children().array().first(where: { $0.tagName() == name }),
              let value = try? child.text(trimAndNormaliseWhitespace: false) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The four fields legacy extracted from the CDATA description (`AQPlusView.swift:182-199`).
    private struct Details {
        var topicTitle: String?
        var initiator: String?
        var comment: String?

        init(description: String) {
            // The feed's own channel blurb is not an item description (`AQPlusView.swift:183-185`).
            guard !description.contains("Pour ne rien rater du meilleur d'HFR, en toutes circonstances") else { return }
            topicTitle = Self.capture(of: /detect[ée]e[^<]*<b>([^<]+)/, in: description)
            initiator = Self.capture(of: />([^<]+)\s+\(initiateur\)/, in: description)
            comment = Self.capture(of: /\(initiateur\)<\/b>\s*:\s*([^<]+)/, in: description)
        }

        /// First capture, trimmed and entity-decoded; nil when absent or empty (legacy tested the raw capture, then trimmed).
        private static func capture(of pattern: Regex<(Substring, Substring)>, in text: String) -> String? {
            let ignoringCase = pattern.ignoresCase()
            guard let match = text.firstMatch(of: ignoringCase) else { return nil }
            let raw = String(match.output.1)
            guard !raw.isEmpty else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return HFRText.decodingHTMLEntities(trimmed) ?? trimmed
        }
    }
}
