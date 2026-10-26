import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HFRModels
import Testing
@testable import HFRNetwork

struct StoredCookieConversionTests {
    /// A whole second one day ahead: Darwin shortens far-future expiries (see `farFutureExpiryIsNeverExtended`).
    private let expiry = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 + 86_400).rounded())

    /// RFC 1123 date as servers write it in `Expires`, e.g. `Sun, 06 Nov 1994 08:49:37 GMT`.
    private func httpDate(_ date: Date) -> String {
        let style = Date.VerbatimFormatStyle(
            format: """
            \(weekday: .abbreviated), \(day: .twoDigits) \(month: .abbreviated) \(year: .defaultDigits) \
            \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits) GMT
            """,
            locale: Locale(identifier: "en_US_POSIX"), timeZone: .gmt, calendar: Calendar(identifier: .gregorian)
        )
        return date.formatted(style)
    }

    private func seconds(_ date: Date?) -> String {
        date.map { String($0.timeIntervalSince1970) } ?? "nil"
    }

    @Test func roundTripKeepsEveryPersistedField() throws {
        let stored = StoredCookie(
            name: "md_user", value: "fake%20pseudo", domain: ".hardware.fr", path: "/",
            expiresDate: expiry, isSecure: true, isHTTPOnly: true
        )
        let cookie = try #require(stored.makeHTTPCookie())
        #expect(cookie.domain == ".hardware.fr")
        #expect(cookie.isSecure)
        #expect(cookie.isHTTPOnly)
        #expect(cookie.expiresDate != nil)
        // The snapshot rounds the expiry back to the second (Darwin may add sub-second noise).
        #expect(StoredCookie(cookie) == stored, "expiry \(seconds(StoredCookie(cookie)?.expiresDate)) vs \(seconds(expiry))")
    }

    @Test func sessionCookieWithoutFlagsRoundTrips() throws {
        let stored = StoredCookie(name: "sid", value: "x", domain: "forum.hardware.fr", path: "/forum")
        let cookie = try #require(stored.makeHTTPCookie())
        #expect(cookie.expiresDate == nil)
        #expect(!cookie.isSecure)
        #expect(!cookie.isHTTPOnly)
        #expect(StoredCookie(cookie) == stored)
    }

    @Test func setCookieHeaderAttributesSurvive() throws {
        let url = try #require(URL(string: "https://forum.hardware.fr/login_validation.php"))
        // corelibs ignores Max-Age, so the lifetime is given as an Expires date.
        let header = "md_user=fake; expires=\(httpDate(expiry)); path=/; domain=.hardware.fr; secure; HttpOnly"
        let cookie = try #require(HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": header], for: url).first)
        let stored = try #require(StoredCookie(cookie))
        #expect(stored.domain == ".hardware.fr")
        #expect(stored.isSecure && stored.isHTTPOnly)
        #expect(stored.expiresDate == expiry, "expiry \(seconds(stored.expiresDate)) vs \(seconds(expiry))")
        let again = StoredCookie(try #require(stored.makeHTTPCookie()))
        #expect(again == stored, "expiry \(seconds(again?.expiresDate)) vs \(seconds(stored.expiresDate))")
    }

    @Test func emptyNameOrDomainIsRejected() {
        #expect(StoredCookie(name: "", value: "v", domain: ".hardware.fr").makeHTTPCookie() == nil)
        #expect(StoredCookie(name: "n", value: "v", domain: "").makeHTTPCookie() == nil)
    }

    @Test func snapshotRoundsExpiryToTheSecond() throws {
        let stored = StoredCookie(name: "n", value: "v", domain: ".hardware.fr", expiresDate: expiry.addingTimeInterval(0.4))
        let cookie = try #require(stored.makeHTTPCookie())
        let snapshot = StoredCookie(cookie)?.expiresDate
        #expect(snapshot == expiry, "expiry \(seconds(snapshot)) vs \(seconds(expiry))")
    }

    /// Darwin returned far-future expiries (2031, 2033) different from the given date on the macOS CI job; RFC 6265bis
    /// caps cookie lifetime at 400 days. Whatever Foundation does, it must never extend a lifetime.
    @Test func farFutureExpiryIsNeverExtended() throws {
        let far = Date(timeIntervalSince1970: 2_000_000_000)
        let cookie = try #require(StoredCookie(name: "n", value: "v", domain: ".hardware.fr", expiresDate: far).makeHTTPCookie())
        let returned = try #require(cookie.expiresDate)
        #expect(returned.timeIntervalSince(far) < 1, "expiry \(seconds(returned)) vs \(seconds(far))")
        #expect(returned.timeIntervalSinceNow > 86_400 * 399, "expiry \(seconds(returned))")
    }

    @Test func expiryIsInclusive() {
        let cookie = StoredCookie(name: "n", value: "v", domain: ".hardware.fr", expiresDate: expiry)
        #expect(!cookie.isExpired(at: expiry.addingTimeInterval(-1)))
        #expect(cookie.isExpired(at: expiry))
        #expect(!StoredCookie(name: "n", value: "v", domain: ".hardware.fr").isExpired(at: .distantFuture))
    }
}
