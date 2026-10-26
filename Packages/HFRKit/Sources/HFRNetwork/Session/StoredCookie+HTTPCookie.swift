import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HFRModels

/// Conversion between the persisted `StoredCookie` (HFRModels) and Foundation's `HTTPCookie`.
///
/// Cookies cross module boundaries only as `StoredCookie` (ARCHITECTURE "Linux rules"); this is the one place that
/// rebuilds the Foundation type. Name, value, domain (leading dot kept), path, expiry, `Secure` and `HttpOnly` survive a
/// round trip; `SameSite`, port lists, comments and version do not (HFR does not use them, audit A §4.1).
extension StoredCookie {
    /// Property key Foundation uses for `HttpOnly` (no public constant exists for it).
    static let httpOnlyPropertyKey = HTTPCookiePropertyKey("HttpOnly")

    /// Snapshot of a Foundation cookie; nil when its name or domain is empty.
    public init?(_ cookie: HTTPCookie) {
        guard !cookie.name.isEmpty, !cookie.domain.isEmpty else { return nil }
        self.init(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
            path: cookie.path.isEmpty ? "/" : cookie.path,
            // Cookie expiry has one-second resolution; Darwin hands the date back with sub-second float noise.
            expiresDate: cookie.expiresDate.map { Date(timeIntervalSince1970: $0.timeIntervalSince1970.rounded()) },
            isSecure: cookie.isSecure,
            isHTTPOnly: cookie.isHTTPOnly
        )
    }

    /// The Foundation cookie to install in a jar; nil when Foundation rejects the properties (empty name or domain).
    public func makeHTTPCookie() -> HTTPCookie? {
        guard !name.isEmpty, !domain.isEmpty else { return nil }
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path.isEmpty ? "/" : path
        ]
        // Absent `expires` makes a session cookie, which is what a nil `expiresDate` means.
        if let expiresDate { properties[.expires] = expiresDate }
        // Foundation treats the mere presence of these keys as true on some platforms: only set them when true.
        if isSecure { properties[.secure] = "TRUE" }
        if isHTTPOnly { properties[Self.httpOnlyPropertyKey] = "TRUE" }
        return HTTPCookie(properties: properties)
    }

    /// True when the cookie has an expiry at or before `now` (session cookies never expire here).
    func isExpired(at now: Date) -> Bool {
        guard let expiresDate else { return false }
        return expiresDate <= now
    }
}
