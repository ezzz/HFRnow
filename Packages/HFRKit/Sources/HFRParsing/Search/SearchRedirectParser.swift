import Foundation
import SwiftSoup

/// Reads the redirect of the global search waiting page (HFR-PROTOCOL S1, S2).
///
/// `POST /search.php?config=hardwarefr.inc` answers "Votre recherche est en cours, merci de bien vouloir patienter..."
/// with a `<meta http-equiv="Refresh" content="1; url=/forum1.php?recherches=1&amp;…">` (capture `R50a`). The results
/// are the page at that URL. Legacy read it with the regex `<meta[^>]*http-equiv=["']?refresh["']?[^>]*content=["']\d+;\s*url=…`
/// and treated a missing match as "Aucune page de résultats n'a été trouvée" (`ObjCForumSearchWorker.m:46-55, 305-321`).
public enum SearchRedirectParser {
    /// The absolute URL the waiting page refreshes to.
    ///
    /// The first `<meta http-equiv="refresh">` whose `content` is `<delay>;url=<target>` wins (the page also holds
    /// `Pragma`, `Cache-Control`, `Expires`… metas). `&amp;` is decoded and a relative target is resolved against the
    /// forum root. The target must be an **`https`** URL on `forum.hardware.fr` (ADR 0006 amendment 1): any other
    /// scheme or host is refused, since this URL is requested with the search session. A plain `http` link to the forum
    /// is upgraded by `HFRURL.absolute` unless it names a port (`http://forum.hardware.fr:80/…` stays `http` and is refused);
    /// `https://forum.hardware.fr:443/…` is accepted.
    /// - Throws: `missingElement` when no refresh meta carries a target (legacy: "no result page"),
    ///   `invalidValue` when the target is not a forum URL.
    public static func redirectURL(in html: String) throws(ParsingError) -> URL {
        let document = try HTMLDocumentLoader.document(from: html)
        let metas: Elements
        do {
            metas = try document.getElementsByTag("meta")
        } catch {
            throw .malformedDocument
        }
        for meta in metas.array() {
            guard
                let equivalent = try? meta.attr("http-equiv"),
                equivalent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "refresh",
                let content = try? meta.attr("content"),
                let target = target(inRefreshContent: content)
            else { continue }
            guard
                let url = HFRURL.absolute(target),
                url.scheme == "https",
                url.host(percentEncoded: false) == HFRURL.forumHost
            else { throw .invalidValue(field: "search redirect URL") }
            return url
        }
        throw .missingElement("meta http-equiv=refresh")
    }

    // MARK: - Implementation

    /// `url=<target>` part of a refresh `content` (`<delay>;url=…`, `,` accepted as HTML does), unquoted; nil when absent.
    private static func target(inRefreshContent content: String) -> String? {
        guard let match = content.wholeMatch(of: refreshPattern) else { return nil }
        var target = String(match.output.1)
        if let quote = target.first, quote == "\"" || quote == "'" {
            target.removeFirst()
            if target.last == quote { target.removeLast() }
        }
        return target.isEmpty ? nil : target
    }

    // `Regex` is not `Sendable` (its output type could hold non-Sendable captures). This literal captures
    // only a `Substring` and the compiled program is initialised atomically by the runtime, so sharing is safe.
    nonisolated(unsafe) private static let refreshPattern =
        /\s*[0-9]+(?:\.[0-9]*)?\s*[;,]\s*url\s*=\s*(.*?)\s*/.ignoresCase()
}
