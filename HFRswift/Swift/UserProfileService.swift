//
//  UserProfileService.swift
//  HFRswift
//
//  Fetches a member profile page with the main account's session and parses it.
//

import Foundation

protocol UserProfileServicing {
    func fetchProfile(url: URL) async throws -> UserProfile
}

struct UserProfileService: UserProfileServicing {
    var session: URLSession = .shared
    var sessionProvider: any UserProfileSessionProviding = LegacyAccountProfileSessionProvider()

    /// Fetches and parses a member profile with the main account's session.
    ///
    /// The cookies are set on the request explicitly (`httpShouldHandleCookies = false`), so the request
    /// neither depends on nor changes `HTTPCookieStorage.shared`. Without a logged-in account no request
    /// is sent (#1349).
    func fetchProfile(url: URL) async throws -> UserProfile {
        guard let cookies = sessionProvider.sessionCookies(for: url) else {
            throw UserProfileLoadingError.loginRequired
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: HFRNetworkTimeout.content
        )
        request.httpShouldHandleCookies = false
        for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200..<300:
                break
            case 401, 403:
                // The forum requires `md_id`, set at login only. An account added before it existed, or one
                // whose cookies lost it, has to be logged in again (#1349).
                let hasMemberID = cookies.contains { $0.name == Self.memberIDCookieName }
                throw hasMemberID ? UserProfileLoadingError.accessDenied : UserProfileLoadingError.reloginRequired
            default:
                throw UserProfileLoadingError.httpStatus(httpResponse.statusCode)
            }
        }

        let html = Self.decodeHTML(data)
        return try UserProfileHTMLParser.parse(html: html, sourceURL: url)
    }

    static let memberIDCookieName = "md_id"

    private static func decodeHTML(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }
        if let cp1252 = String(data: data, encoding: .windowsCP1252) {
            return cp1252
        }
        return String(decoding: data, as: UTF8.self)
    }
}
