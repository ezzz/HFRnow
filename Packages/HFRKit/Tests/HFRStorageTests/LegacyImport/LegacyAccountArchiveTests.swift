#if canImport(Darwin)
import Foundation
import HFRModels
import HFRStorage
import Testing

/// Replays legacy's writer (`MultisManager.m:49-80`: an `NSKeyedArchiver` of an `NSArray` of `NSMutableDictionary` with
/// `NSHTTPCookie`s) on the `storage-keychain.json` synthetic accounts, then decodes it. The real item is a Mac check (M1).
@Suite("Legacy account archive (LOT-067, Darwin)")
struct LegacyAccountArchiveTests {
    private func cookie(_ name: String, _ value: String, secure: Bool) throws -> HTTPCookie {
        try #require(HTTPCookie(properties: [
            .name: name, .value: value, .domain: ".hardware.fr", .path: "/",
            .expires: Date(timeIntervalSince1970: 1_803_859_200), .secure: secure ? "TRUE" : "FALSE"
        ]))
    }

    private func legacyArchive() throws -> Data {
        let first = NSMutableDictionary()
        first["PSEUDO"] = "fakeuser1"
        first["PSEUDO_DISPLAY"] = "fakeuser1"
        first["COOKIES"] = [try cookie("md_user", "fakeuser1", secure: false), try cookie("md_passs", "fakepasshash1", secure: true)]
        first["HASH"] = "0123456789abcdef0123456789abcdef01234567"
        first["AVATAR"] = Data([0x47, 0x49, 0x46])
        first["MAIN"] = NSNumber(value: false)
        let second = NSMutableDictionary()
        second["PSEUDO"] = "fakeuser2"
        second["PSEUDO_DISPLAY"] = "FakeUser2"
        second["COOKIES"] = [try cookie("md_user", "fakeuser2", secure: false)]
        second["MAIN"] = NSNumber(value: true)
        return try NSKeyedArchiver.archivedData(withRootObject: NSArray(array: [first, second]), requiringSecureCoding: false)
    }

    @Test("decodes every field of the legacy archive")
    func decode() throws {
        let records = try LegacyAccountArchive.decode(try legacyArchive())
        #expect(records.count == 2)
        #expect(records[0].pseudo == "fakeuser1")
        #expect(records[0].hashCheck == "0123456789abcdef0123456789abcdef01234567")
        #expect(records[0].avatarData == Data([0x47, 0x49, 0x46]))
        #expect(records[0].cookies.map(\.name) == ["md_user", "md_passs"])
        #expect(records[0].cookies[1].isSecure)
        #expect(records[0].cookies[1].expiresDate == Date(timeIntervalSince1970: 1_803_859_200))
        #expect(records[1].displayName == "FakeUser2")
        #expect(records[1].isMain && !records[0].isMain)
    }

    @Test("bytes that are not a legacy archive are unreadable")
    func notAnArchive() throws {
        #expect(throws: LegacyImportError.sourceUnreadable) { try LegacyAccountArchive.decode(Data("garbage".utf8)) }
        let wrongRoot = try NSKeyedArchiver.archivedData(withRootObject: "text", requiringSecureCoding: false)
        #expect(throws: LegacyImportError.sourceUnreadable) { try LegacyAccountArchive.decode(wrongRoot) }
    }
}
#endif
