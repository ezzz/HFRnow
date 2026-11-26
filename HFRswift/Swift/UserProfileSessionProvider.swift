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

/// Reads the cookies of the main account kept by the legacy `MultisManager`.
///
/// The cookies are read from the account itself rather than from `HTTPCookieStorage.shared`, whose content depends on
/// whatever the rest of the app last did with it (logout, account switch, reply posting all wipe and refill it).
/// When the account record holds no usable cookie, the shared storage is used as a fallback.
struct LegacyAccountProfileSessionProvider: UserProfileSessionProviding {
    var accountsManager: any LegacyAccountsManaging = ObjCLegacyAccountsManager.shared
    /// The cookies used when the account record holds none (defaults to `HTTPCookieStorage.shared`).
    var fallbackCookies: (URL) -> [HTTPCookie] = { HTTPCookieStorage.shared.cookies(for: $0) ?? [] }
    var now: () -> Date = { .now }

    func sessionCookies(for url: URL) -> [HTTPCookie]? {
        let date = now()
        let accountCookies = (mainCompte()?[Self.cookiesKey] as? [HTTPCookie]) ?? []
        if let cookies = Self.usableSessionCookies(accountCookies, for: url, at: date) {
            return cookies
        }
        return Self.usableSessionCookies(fallbackCookies(url), for: url, at: date)
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
