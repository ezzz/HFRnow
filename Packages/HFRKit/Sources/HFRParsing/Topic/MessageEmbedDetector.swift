import Foundation
import HFRModels
import SwiftSoup

/// Finds the video links of a message that the reader can play inline (LOT-035, audit C09): legacy's rule
/// (`ParseMessagesOperation.m:238-317`), on the normalized content of LOT-034.
///
/// A candidate is an `a.cLink` that is a child of a top-level element of the content (legacy: the link's third ancestor
/// is `td.messCase2`, `:260-264`) and holds only text: a link in a quote, a spoiler or a list, or around an image, is
/// left as a link. The signature is not part of `MessageContent.html`, so its links never are (`:263`). The link must
/// match one of legacy's four hosts (`:241-244`); Dailymotion, Coub and Twitch stay links, as legacy had them commented
/// out (`:247-257`). The player URL is built from the extracted id, never copied from the page.
public enum MessageEmbedDetector {
    /// The embeds of a normalized `MessageContent.html`, in page order.
    public static func embeds(inNormalizedHTML html: String) throws(ParsingError) -> [MessageEmbed] {
        // Most messages have no link at all: skip the second parse.
        guard html.contains("cLink") else { return [] }
        guard let body = (try? SwiftSoup.parseBodyFragment(html))?.body() else { throw .malformedDocument }
        let links = (try? body.select("a.cLink").array()) ?? []
        return links.compactMap { link in
            guard link.parent()?.parent() === body, link.children().isEmpty,
                  let href = try? link.attr("href"), let url = URL(string: href)
            else { return nil }
            return embed(for: url)
        }
    }

    /// The embed of one link, when it is a video of a supported host.
    ///
    /// - YouTube: `youtube.com` (also `www.`, `m.`, `gaming.`) with a `v=` parameter, or `youtu.be/<id>`: player
    ///   `https://www.youtube.com/embed/<id>`, with `?start=<seconds>` from the link's `t` parameter (`startSeconds`).
    /// - Vimeo: `vimeo.com/[<word>/…]<number>`: `https://player.vimeo.com/video/<number>`.
    /// - Streamable: `https://streamable.com/<id>`: `https://streamable.com/s/<id>`.
    public static func embed(for url: URL) -> MessageEmbed? {
        let href = url.absoluteString
        // The four legacy patterns (`:241-244`), with their host dots escaped (legacy's `.` matched any character).
        if let match = href.firstMatch(of: /^https?:\/\/(?:www\.|m\.|gaming\.)?youtube\.com\/.+v=([\w-]+)\/?/)
            ?? href.firstMatch(of: /^https?:\/\/youtu\.be\/([\w-]+)\/?/) {
            let start = startSeconds(in: url)
            let player = "https://www.youtube.com/embed/" + match.output.1 + (start.map { "?start=\($0)" } ?? "")
            return URL(string: player).map { MessageEmbed(provider: .youtube, sourceURL: url, embedURL: $0, startSeconds: start) }
        }
        if let match = href.firstMatch(of: /^https?:\/\/vimeo\.com\/(?:[a-zA-Z]+\/)*([0-9]+)/) {
            return URL(string: "https://player.vimeo.com/video/" + match.output.1)
                .map { MessageEmbed(provider: .vimeo, sourceURL: url, embedURL: $0) }
        }
        if let match = href.firstMatch(of: /^https:\/\/streamable\.com\/([\w]+)\/?/) {
            return URL(string: "https://streamable.com/s/" + match.output.1)
                .map { MessageEmbed(provider: .streamable, sourceURL: url, embedURL: $0) }
        }
        return nil
    }

    /// The start offset of a YouTube link, from its last `t` query parameter: plain seconds (`t=706`, as YouTube reads
    /// it) or `[<h>h][<m>m][<s>s]` (`t=1h2m3s` is 3723 s; legacy computed minutes × 3600 for the hours, `:281`, and read
    /// only a final `t=` ending in `s`, `:275`). Nil without `t`, for zero, or for any other form.
    static func startSeconds(in url: URL) -> Int? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let value = items.last(where: { $0.name == "t" })?.value else { return nil }
        let seconds: Int?
        if let plain = value.wholeMatch(of: /[0-9]{1,6}/) {
            seconds = Int(plain.output)
        } else if let parts = value.wholeMatch(of: /(?:([0-9]{1,4})h)?(?:([0-9]{1,4})m)?(?:([0-9]{1,6})s)?/), !value.isEmpty {
            let (_, hours, minutes, rest) = parts.output
            let number = { (part: Substring?) in part.flatMap { Int($0) } ?? 0 }
            seconds = number(hours) * 3600 + number(minutes) * 60 + number(rest)
        } else {
            seconds = nil
        }
        return seconds.flatMap { $0 > 0 ? $0 : nil }
    }
}
