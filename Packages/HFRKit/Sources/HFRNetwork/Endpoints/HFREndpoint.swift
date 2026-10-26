import Foundation
import HFRModels

/// Typed builders for every HFR endpoint documented in HFR-PROTOCOL §1–2.
///
/// Pure: each builder returns an `HTTPRequest` and never touches the network, cookies or the session.
/// Cookies, `hash_check` ownership and redirects handling beyond the request's `redirectPolicy` belong to the callers.
/// Invalid input (page below 1, private category in a forum list, too short a query) throws `NetworkError.invalidRequest`.
public enum HFREndpoint {
    /// Scheme and host of the forum (`Classes/k.m:37-40`).
    public static let host = "https://forum.hardware.fr"
    /// The `config` of every page except the global search (HFR-PROTOCOL header).
    static let config = "hfr.inc"
    /// The `config` of the global search only (`ObjCForumSearchWorker.m:31`).
    static let searchConfig = "hardwarefr.inc"

    /// R1: the home page, with the forum list, `hash_check` and the private message count (`ObjCForumsLoaderWorker.m:20`).
    public static func home() throws -> HTTPRequest {
        try .get(url(path: "/"))
    }

    /// R8: the home page fetched by the background private message check, with its short time limit
    /// (`MPBackgroundService.swift:80-135`).
    public static func privateMessageCheck() throws -> HTTPRequest {
        try .get(url(path: "/"), timeout: RequestTimeout.background)
    }

    /// R3: favourites across forums (`ObjCFavoritesLoaderWorker.m:46-48`).
    ///
    /// `owntopic` is 3 (favourites) by default, or 1 (tracked topics) when the legacy `vos_sujets` setting is not 1.
    /// Other filters are refused: `forum1f.php` only knows those two.
    public static func favorites(filter: TopicListFilter = .favorites) throws -> HTTPRequest {
        guard filter == .favorites || filter == .flagged else {
            throw NetworkError.invalidRequest(reason: "forum1f.php only lists tracked topics or favourites")
        }
        return try .get(url(path: "/forum1f.php", query: [("owntopic", String(filter.rawValue))]))
    }

    /// R4: the private message list (`ObjCMPTopicsLoaderWorker.m:9`); legacy only ever reads page 1.
    public static func privateMessages(page: Int = 1) throws -> HTTPRequest {
        try requirePage(page)
        return try .get(url(path: "/forum1.php", query: [
            ("config", config), ("cat", CategoryID.privateMessages.queryValue), ("page", String(page))
        ]))
    }

    /// R6: the account's own profile editor, `page=5` for `hash_check` and avatar, `page=1` for a cookie refresh.
    public static func editProfile(page: EditProfilePage) throws -> HTTPRequest {
        try .get(url(path: "/user/editprofil.php", query: [("config", config), ("page", String(page.rawValue))]))
    }

    /// R9: the public profile page of a member (`UserProfileView.swift:113-430`).
    public static func publicProfile(memberID: Int) throws -> HTTPRequest {
        guard memberID >= 0 else { throw NetworkError.invalidRequest(reason: "negative member id") }
        return try .get(url(path: "/hfr/profil-\(memberID).htm"))
    }

    /// Turns a link found in a page (relative like `/forum2.php?…`, protocol-relative, or absolute) into an absolute URL.
    ///
    /// Only the forum's own host is accepted, over `http` or `https`; anything else returns nil.
    public static func absoluteURL(href: String) -> URL? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let base = URL(string: host), let url = URL(string: trimmed, relativeTo: base)?.absoluteURL else {
            return nil
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host()?.lowercased() == base.host()?.lowercased() else { return nil }
        return url
    }

    /// Builds `host + path + ?query` with each value percent-encoded; query order is the array order.
    static func url(path: String, query: [(name: String, value: String)] = [], literals: Set<UInt8> = []) throws -> URL {
        var text = host + path
        if !query.isEmpty {
            text += "?" + query.map { "\($0.name)=\(QueryEncoding.encode($0.value, extraLiterals: literals))" }.joined(separator: "&")
        }
        guard let url = URL(string: text) else { throw NetworkError.invalidRequest(reason: "malformed endpoint URL") }
        return url
    }

    /// Refuses pages below 1, which HFR does not serve.
    static func requirePage(_ page: Int) throws {
        guard page >= 1 else { throw NetworkError.invalidRequest(reason: "page must be 1 or more") }
    }
}
