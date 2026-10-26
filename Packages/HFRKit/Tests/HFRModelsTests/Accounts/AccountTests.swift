import Foundation
import Testing
@testable import HFRModels

@Suite struct AccountTests {
    private func cookie(_ name: String = "md_user", domain: String = ".hardware.fr") -> StoredCookie {
        StoredCookie(
            name: name,
            value: "SECRET-VALUE",
            domain: domain,
            path: "/",
            expiresDate: Date(timeIntervalSince1970: 1_800_000_000),
            isSecure: true,
            isHTTPOnly: true
        )
    }

    @Test func cookieRoundTripsEveryField() throws {
        let original = cookie()
        let decoded = try roundTrip(original)
        #expect(decoded == original)
        #expect(decoded.expiresDate == original.expiresDate)
        #expect(decoded.isSecure && decoded.isHTTPOnly)
    }

    @Test func sessionCookieHasNoExpiry() throws {
        let session = StoredCookie(name: "a", value: "b", domain: "forum.hardware.fr")
        #expect(session.expiresDate == nil)
        #expect(session.path == "/")
        #expect(try roundTrip(session) == session)
    }

    @Test func jarKeyIgnoresCaseAndLeadingDotOfTheDomain() {
        #expect(cookie(domain: ".Hardware.fr").jarKey == cookie(domain: "hardware.fr").jarKey)
        #expect(cookie("a").jarKey != cookie("b").jarKey)
        #expect(cookie(domain: "hardware.fr").jarKey != cookie(domain: "forum.hardware.fr").jarKey)
    }

    @Test func cookieDescriptionsNeverContainTheValue() {
        let value = cookie()
        #expect(!value.description.contains("SECRET-VALUE"))
        #expect(!value.debugDescription.contains("SECRET-VALUE"))
        #expect(!"\(value)".contains("SECRET-VALUE"))
    }

    @Test func accountRoundTripsWithSecretsAndAvatar() throws {
        let account = Account(
            pseudo: "alice",
            displayName: "Alice",
            cookies: [cookie()],
            hashCheck: "HASH-SECRET",
            avatarData: Data([1, 2, 3]),
            isMain: true
        )
        let decoded = try roundTrip(account)
        #expect(decoded == account)
        #expect(decoded.avatarData == Data([1, 2, 3]))
    }

    @Test func accountIdentityIsThePseudoAndDisplayNameDefaultsToIt() {
        let account = Account(pseudo: "alice")
        #expect(account.id == "alice")
        #expect(account.displayName == "alice")
        #expect(account.cookies.isEmpty && account.hashCheck == nil && !account.isMain)
    }

    @Test func accountDescriptionNeverContainsSecrets() {
        let account = Account(pseudo: "alice", cookies: [cookie()], hashCheck: "HASH-SECRET")
        #expect(!account.description.contains("HASH-SECRET"))
        #expect(!account.debugDescription.contains("SECRET-VALUE"))
        #expect(!"\(account)".contains("HASH-SECRET"))
    }

    @Test func accountsDifferingOnlyInTheTokenAreDifferent() {
        #expect(Account(pseudo: "a", hashCheck: "1") != Account(pseudo: "a", hashCheck: "2"))
    }

    @Test func reflectionNeverRevealsSecrets() {
        let account = Account(pseudo: "alice", cookies: [cookie()], hashCheck: "HASH-SECRET")
        var accountDump = ""
        var cookieDump = ""
        dump(account, to: &accountDump)
        dump(cookie(), to: &cookieDump)
        #expect(!accountDump.contains("HASH-SECRET") && !accountDump.contains("SECRET-VALUE"))
        #expect(!cookieDump.contains("SECRET-VALUE"))
        #expect(!String(reflecting: account).contains("HASH-SECRET"))
        #expect(accountDump.contains("alice"))
        #expect(cookieDump.contains("md_user"))
    }
}
