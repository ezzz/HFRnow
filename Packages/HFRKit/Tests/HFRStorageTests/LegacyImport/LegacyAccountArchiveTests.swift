#if canImport(Darwin)
import Foundation
import Synchronization
import HFRModels
import HFRStorage
import Testing

/// Replays legacy's writer (`MultisManager.m:49-80`: an `NSKeyedArchiver` of an `NSArray` of `NSMutableDictionary` with
/// `NSHTTPCookie`s) on the `storage-keychain.json` synthetic accounts, then decodes it. The real item is a Mac check (M1).
@Suite("Legacy account archive (LOT-067, Darwin)")
struct LegacyAccountArchiveTests {
    private func cookie(_ name: String, _ value: String, secure: Bool, httpOnly: Bool = false) throws -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: ".hardware.fr", .path: "/",
            .expires: Date(timeIntervalSince1970: 1_803_859_200)
        ]
        // Foundation reads these two flags by presence, as a cookie parsed from a response carries them.
        if secure { properties[.secure] = "TRUE" }
        if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        return try #require(HTTPCookie(properties: properties))
    }

    private func legacyArchive() throws -> Data {
        let first = NSMutableDictionary()
        first["PSEUDO"] = "fakeuser1"
        first["PSEUDO_DISPLAY"] = "fakeuser1"
        first["COOKIES"] = [
            try cookie("md_user", "fakeuser1", secure: false),
            try cookie("md_passs", "fakepasshash1", secure: true, httpOnly: true)
        ]
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
        #expect(records[0].cookies[1].isSecure && records[0].cookies[1].isHTTPOnly)
        #expect(!records[0].cookies[0].isSecure && !records[0].cookies[0].isHTTPOnly)
        #expect(records[0].cookies[1].domain == ".hardware.fr" && records[0].cookies[1].path == "/")
        #expect(records[0].cookies[1].value == "fakepasshash1")
        #expect(records[0].cookies[1].expiresDate == Date(timeIntervalSince1970: 1_803_859_200))
        #expect(records[1].displayName == "FakeUser2")
        #expect(records[1].isMain && !records[0].isMain)
    }

    @Test("an archive naming a class outside the legacy format is refused, never instantiated")
    func unexpectedClass() throws {
        let entry = NSMutableDictionary()
        entry["PSEUDO"] = "fakeuser1"
        entry["EXTRA"] = UnexpectedArchivedObject()
        let archive = try NSKeyedArchiver.archivedData(withRootObject: NSArray(array: [entry]), requiringSecureCoding: false)
        #expect(throws: LegacyImportError.sourceUnreadable) { try LegacyAccountArchive.decode(archive) }
        #expect(!UnexpectedArchivedObject.instantiated.withLock { $0 })
    }

    @Test("a cookie whose archived properties hold a class outside the legacy format is refused")
    func forgedCookie() throws {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName("NSHTTPCookie", for: ForgedCookie.self)
        let entry = NSDictionary(dictionary: ["PSEUDO": "fakeuser1", "COOKIES": NSArray(array: [ForgedCookie()])])
        archiver.encode(NSArray(array: [entry]), forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        #expect(throws: LegacyImportError.sourceUnreadable) { try LegacyAccountArchive.decode(archiver.encodedData) }
    }

    @Test("bytes that are not a legacy archive are unreadable")
    func notAnArchive() throws {
        #expect(throws: LegacyImportError.sourceUnreadable) { try LegacyAccountArchive.decode(Data("garbage".utf8)) }
        let wrongRoot = try NSKeyedArchiver.archivedData(withRootObject: "text", requiringSecureCoding: false)
        #expect(throws: LegacyImportError.sourceUnreadable) { try LegacyAccountArchive.decode(wrongRoot) }
    }
}

/// A class no legacy archive holds (#1205): its decoder must never run.
@objc(HFRTestUnexpectedArchivedObject)
private final class UnexpectedArchivedObject: NSObject, NSCoding {
    static let instantiated = Mutex(false)

    override init() {}

    init?(coder: NSCoder) {
        Self.instantiated.withLock { $0 = true }
    }

    func encode(with coder: NSCoder) {}
}

/// Archived under the name `NSHTTPCookie`, the way `NSHTTPCookie` archives itself (its properties as the unkeyed
/// object `$0`), but with a class outside the legacy format inside those properties.
@objc(HFRTestForgedCookie)
private final class ForgedCookie: NSObject, NSCoding {
    override init() {}

    init?(coder: NSCoder) { nil }

    func encode(with coder: NSCoder) {
        coder.encode(NSDictionary(dictionary: ["Name": "md_user", "Value": UnexpectedArchivedObject()]))
    }
}
#endif
