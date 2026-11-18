import Foundation
import SwiftSoup

/// A plain link to one YouTube video in a message (#1037): what the reader needs to show its thumbnail and to open it.
public struct YouTubeVideoLink: Equatable, Sendable {
    /// The link as posted.
    public let sourceURL: URL
    /// The video id: letters, digits, `_` and `-` only.
    public let videoID: String
    /// The start offset of the link's `t` parameter (LOT-035 rules), nil without one.
    public let startSeconds: Int?

    /// The thumbnail: `https://i.ytimg.com/vi/<id>/hqdefault.jpg`, the 480×360 image YouTube serves for every video. A de-facto
    /// form, not documented by YouTube (operator decision of 2026-11-18 on #1037; HFR-PROTOCOL §6c, LOT-071 T9).
    public var thumbnailURL: URL {
        // The id is `[\w-]+` by construction, so the string is always a valid URL.
        URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg") ?? sourceURL
    }

    /// The link to hand to the system: the posted one over `https` (a universal link needs it; YouTube serves every host over `https`).
    public var openURL: URL {
        guard sourceURL.scheme?.lowercased() == "http", var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false)
        else { return sourceURL }
        components.scheme = "https"
        return components.url ?? sourceURL
    }
}

/// Finds the plain YouTube video links of a message that the reader shows as a thumbnail card (#1037).
///
/// A card is for an `a.cLink` that holds text only, whose text is the link's own address (a named link stays a text link), outside
/// any table (quotes, spoilers and code are tables) and that is not one of LOT-035's player candidates: those keep their player
/// placeholder (LOT-108) and are not touched. The signature is not part of `MessageContent.html`, so its links never get a card.
public enum YouTubeLinkDetector {
    /// The video of `url`: `youtu.be/<id>`, `youtube.com/watch?v=<id>` (also `www.` and `m.`) and `youtube.com/shorts/<id>`, over
    /// `http(s)`, without user info. A channel, a playlist, a handle or any other YouTube page is nil.
    public static func video(for url: URL) -> YouTubeVideoLink? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.user() == nil, url.password() == nil,
              let host = url.host(percentEncoded: true)?.lowercased() else { return nil }
        let id: Substring
        if host == "youtu.be" {
            guard let match = url.path(percentEncoded: true).wholeMatch(of: /\/([\w-]+)\/?/) else { return nil }
            id = match.output.1
        } else if host == "youtube.com" || host == "www.youtube.com" || host == "m.youtube.com" {
            let path = url.path(percentEncoded: true)
            if let match = path.wholeMatch(of: /\/shorts\/([\w-]+)\/?/) {
                id = match.output.1
            } else if path == "/watch" || path == "/watch/" {
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                guard let value = items.last(where: { $0.name == "v" })?.value, let match = value.wholeMatch(of: /[\w-]+/) else {
                    return nil
                }
                id = match.output
            } else {
                return nil
            }
        } else {
            return nil
        }
        return YouTubeVideoLink(sourceURL: url, videoID: String(id), startSeconds: MessageEmbedDetector.startSeconds(in: url))
    }

    /// The cards of a normalized `MessageContent.html`, in page order.
    public static func cards(inNormalizedHTML html: String) throws(ParsingError) -> [YouTubeVideoLink] {
        // Most messages have no YouTube link at all: skip the second parse.
        guard html.contains("cLink"), html.localizedStandardContains("youtu") else { return [] }
        guard let body = (try? SwiftSoup.parseBodyFragment(html))?.body() else { throw .malformedDocument }
        let links = (try? body.select("a.cLink").array()) ?? []
        return links.compactMap { link in
            guard link.children().isEmpty, link.childNodeSize() > 0, !MessageEmbedDetector.isCandidate(link, in: body),
                  !hasTableAncestor(link), let href = try? link.attr("href"), let url = URL(string: href),
                  let video = video(for: url), let text = try? link.text(), isAddress(text, of: href) else { return nil }
            return video
        }
    }

    /// Walks up with a loop: SwiftSoup's `parents()` recurses per level (AGENTS.md learnings, LOT-032).
    private static func hasTableAncestor(_ element: Element) -> Bool {
        var current = element.parent()
        while let node = current {
            if node.tagName() == "table" { return true }
            current = node.parent()
        }
        return false
    }

    /// The link text is the address itself, ignoring case, spaces around it, the scheme and a trailing `/`.
    private static func isAddress(_ text: String, of href: String) -> Bool {
        func bare(_ value: String) -> String {
            var result = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let scheme = result.firstMatch(of: /^https?:\/\//) { result.removeSubrange(scheme.range) }
            while result.hasSuffix("/") { result.removeLast() }
            return result
        }
        return !bare(text).isEmpty && bare(text) == bare(href)
    }
}
