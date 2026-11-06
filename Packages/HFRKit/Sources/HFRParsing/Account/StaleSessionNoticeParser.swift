import Foundation
import SwiftSoup

/// Recognizes the page HFR serves, instead of the requested one, to a jar whose `md_passs` it refuses (#383).
///
/// With the account's `md_user` and `md_id` and a wrong `md_passs`, the home page, `forum1f.php?owntopic=1` and profile
/// pages 1 and 5 all answer the same bytes (`R70a`–`R70d`): a lone `.hop` "Identifiants invalides !" with
/// `Refresh: 1; url=/unlog.php?config=hfr.inc`. The page is recognized by that sentence **and** that refresh target, never
/// by its size: the cookie-less answer of the profile pages (`R71a`, `R71b`) is a `.hop` too, with another sentence
/// ("Mot de passe incorrect !") and a refresh to `login.php`, and stays unrecognized here. Anything that differs in
/// either part (another sentence, a link or input in the block, another target) is not this page.
///
/// The refresh target is only read, never requested: `unlog.php` without its `codehex` token does nothing (`R72a`).
public enum StaleSessionNoticeParser {
    /// The whole `.hop` text of the stale-session page, whitespace collapsed (`R70a`–`R70d`).
    static let sentence = "Identifiants invalides !"
    /// The path and query of its refresh target (`R70a`–`R70d`).
    static let refreshPath = "/unlog.php"
    static let refreshQuery = "config=hfr.inc"
    /// The target's file name, which the raw page must contain before it is parsed.
    static let unlogFileName = "unlog.php"

    /// True when `html` is HFR's stale-session page; `requestURL` resolves a relative refresh target.
    ///
    /// The status code and the URL the page was served at are not read here: callers check them first.
    /// - Throws: `malformedDocument` when the HTML backend cannot read the page.
    public static func isStaleSessionNotice(html: String, requestURL: URL = HFRURL.base) throws(ParsingError) -> Bool {
        // Every caller runs this on ordinary pages first (a 65 KB home, `R02`): skip the parse when the target's file name
        // is absent. A target spelled with character references then reads as not this page, the conservative side.
        guard html.contains(unlogFileName) else { return false }
        let document = try HTMLDocumentLoader.document(from: html)
        let hops = document.descendants(matching: .exact("hop"))
        guard hops.count == 1, let hop = hops.first else { return false }
        if let found = try? hop.select("a, input, form, button, textarea, select"), !found.isEmpty() { return false }
        guard let text = try? hop.text(), collapsed(text) == sentence else { return false }
        guard let target = refreshTarget(in: document, requestURL: requestURL) else { return false }
        return isUnlogTarget(target)
    }

    // MARK: - Implementation

    /// Target of the page's only refresh meta; nil when there is none or more than one.
    private static func refreshTarget(in document: Document, requestURL: URL) -> URL? {
        guard let metas = try? document.getElementsByTag("meta") else { return nil }
        let refreshes = metas.array().filter { meta in
            guard let equivalent = try? meta.attr("http-equiv") else { return false }
            return equivalent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "refresh"
        }
        guard
            refreshes.count == 1,
            let content = try? refreshes[0].attr("content"),
            let raw = SearchRedirectParser.target(inRefreshContent: content)
        else { return nil }
        return HFRURL.absolute(raw, relativeTo: requestURL)
    }

    /// `https://forum.hardware.fr/unlog.php?config=hfr.inc` exactly (port absent or 443, no fragment).
    private static func isUnlogTarget(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return false }
        return components.scheme == "https"
            && components.host == HFRURL.forumHost
            && (components.port == nil || components.port == 443)
            && components.user == nil && components.password == nil
            && components.path == refreshPath
            && components.query == refreshQuery
            && components.fragment == nil
    }

    private static func collapsed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
