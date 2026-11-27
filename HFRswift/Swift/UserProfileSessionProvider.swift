//
//  UserProfileSessionProvider.swift
//  HFRswift
//
//  Supplies the forum session cookies sent with a member profile request.
//  Since November 2026 the forum answers 403 to anonymous requests on `/hfr/profil-<id>.htm` (#1349).
//

import Foundation

/// Supplies the session cookies a profile request must carry.
protocol UserProfileSessionProviding {
    /// Cookies of the active account that apply to `url`, or `nil` when no account is logged in.
    func sessionCookies(for url: URL) -> [HTTPCookie]?
}

/// Builds the cookies of a profile request from the main account kept by the legacy `MultisManager` and from the
/// cookies the forum set during the session (`HTTPCookieStorage.shared`).
///
/// `md_user` / `md_passs` alone are not enough: the forum also requires the `p` cookie it sets on every page view,
/// which the account record does not hold (#1349). The account's cookies win for the names they define, so the
/// identity is always the main account's; the stored cookies add everything else.
struct LegacyAccountProfileSessionProvider: UserProfileSessionProviding {
    var accountsManager: any LegacyAccountsManaging = ObjCLegacyAccountsManager.shared
    /// The cookies the forum set during the session (defaults to `HTTPCookieStorage.shared`).
    var storedCookies: (URL) -> [HTTPCookie] = { HTTPCookieStorage.shared.cookies(for: $0) ?? [] }
    var now: () -> Date = { .now }

    func sessionCookies(for url: URL) -> [HTTPCookie]? {
        let date = now()
        let accountCookies = Self.applicable((mainCompte()?[Self.cookiesKey] as? [HTTPCookie]) ?? [], to: url, at: date)
        let accountNames = Set(accountCookies.map(\.name))
        let stored = Self.applicable(storedCookies(url), to: url, at: date).filter { !accountNames.contains($0.name) }
        return Self.usableSessionCookies(accountCookies + stored, for: url, at: date)
    }

    private static func applicable(_ cookies: [HTTPCookie], to url: URL, at date: Date) -> [HTTPCookie] {
        cookies.filter { applies($0, to: url) && !isExpired($0, at: date) }
    }

    /// The cookies of `cookies` that apply to `url` at `date`, or `nil` when they hold no logged-in `md_user` cookie.
    static func usableSessionCookies(_ cookies: [HTTPCookie], for url: URL, at date: Date) -> [HTTPCookie]? {
        let applicable = cookies.filter { cookie in
            applies(cookie, to: url) && !isExpired(cookie, at: date)
        }
        let isLoggedIn = applicable.contains { $0.name == "md_user" && !$0.value.isEmpty && $0.value != "deleted" }
        return isLoggedIn ? applicable : nil
    }

    private static let cookiesKey = "COOKIES"

    private func mainCompte() -> LegacyRawCompte? {
        if let compte = accountsManager.mainCompte() {
            return compte
        }
        return accountsManager.comptes().first { ($0["MAIN"] as? NSNumber)?.boolValue ?? false }
    }

    private static func isExpired(_ cookie: HTTPCookie, at date: Date) -> Bool {
        guard let expiresDate = cookie.expiresDate else { return false }
        return expiresDate <= date
    }

    private static func applies(_ cookie: HTTPCookie, to url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        if cookie.isSecure, url.scheme?.lowercased() != "https" {
            return false
        }

        let domain = cookie.domain.lowercased()
        let bareDomain = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        let domainMatches = host == bareDomain || host.hasSuffix("." + bareDomain)
        guard domainMatches else { return false }

        let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
        return url.path().hasPrefix(cookiePath)
    }
}
