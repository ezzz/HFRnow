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

    @Test("a cookie whose archived properties hold a class outside the legacy format is refused, never instantiated")
    func forgedCookie() throws {
        let forged = ForgedCookie(["Name": "md_user", "Value": UnexpectedArchivedObject()])
        #expect(throws: LegacyImportError.sourceUnreadable) { try LegacyAccountArchive.decode(try archive(forged)) }
        #expect(!UnexpectedArchivedObject.instantiated.withLock { $0 })
    }

    @Test("a cookie carrying every property NSHTTPCookie archives is kept")
    func everyArchivedProperty() throws {
        let full = try #require(HTTPCookie(properties: [
            .name: "md_id", .value: "1", .domain: ".hardware.fr", .path: "/", .version: "1", .comment: "c",
            .commentURL: "https://forum.hardware.fr/", .port: "80,443", .discard: "TRUE", .sameSitePolicy: "lax",
            .secure: "TRUE", HTTPCookiePropertyKey("HttpOnly"): "TRUE", .expires: Date(timeIntervalSince1970: 1_803_859_200)
        ]))
        let entry = NSDictionary(dictionary: ["PSEUDO": "fakeuser1", "COOKIES": NSArray(array: [full])])
        let data = try NSKeyedArchiver.archivedData(withRootObject: NSArray(array: [entry]), requiringSecureCoding: false)
        let cookies = try #require(try LegacyAccountArchive.decode(data).first).cookies
        #expect(cookies.map(\.name) == ["md_id"])
        #expect(cookies.first?.isSecure == true && cookies.first?.isHTTPOnly == true)
        #expect(cookies.first?.value == "1" && cookies.first?.domain == ".hardware.fr")
    }

    /// Each key `NSHTTPCookie` archives, given a dictionary: `HTTPCookie(properties:)` raises an Objective-C exception
    /// (`Path`, `Comment`, `CommentURL`, `SameSite`) or crashes (`Port`) on some, and reads others by presence alone.
    @Test("a cookie whose archived property has an unexpected type is skipped, never handed to Foundation", arguments: [
        "Name", "Value", "Domain", "Path", "Expires", "Created", "Secure", "HttpOnly", "Discard", "Version", "Max-Age",
        "Comment", "CommentURL", "OriginURL", "SameSite", "Port"
    ])
    func mistypedProperty(key: String) throws {
        var properties = Self.archivedProperties
        properties[key] = NSDictionary(dictionary: ["k": "v"])
        let records = try LegacyAccountArchive.decode(try archive(ForgedCookie(properties), ForgedCookie(Self.archivedProperties)))
        #expect(records.first?.cookies.map(\.name) == ["md_user"])
        #expect(records.first?.cookies.first?.isSecure == false)
    }

    @Test("a property key NSHTTPCookie does not archive is dropped, the cookie kept")
    func unknownProperty() throws {
        var properties = Self.archivedProperties
        properties["Partitioned"] = NSDictionary(dictionary: ["k": "v"])
        let records = try LegacyAccountArchive.decode(try archive(ForgedCookie(properties)))
        #expect(records.first?.cookies.map(\.name) == ["md_user"])
    }

    @Test("bytes that are not a legacy archive are unreadable")
    func notAnArchive() throws {
        #expect(throws: LegacyImportError.sourceUnreadable) { try LegacyAccountArchive.decode(Data("garbage".utf8)) }
        let wrongRoot = try NSKeyedArchiver.archivedData(withRootObject: "text", requiringSecureCoding: false)
        #expect(throws: LegacyImportError.sourceUnreadable) { try LegacyAccountArchive.decode(wrongRoot) }
    }
}

extension LegacyAccountArchiveTests {
    /// The properties `NSHTTPCookie` archives for a cookie parsed from a response (measured on macOS 27.2).
    fileprivate static var archivedProperties: [String: Any] {
        [
            "Name": "md_user", "Value": "fakeuser1", "Domain": ".hardware.fr", "Path": "/",
            "Expires": Date(timeIntervalSince1970: 1_803_859_200), "Created": NSNumber(value: 817_457_422.0)
        ]
    }

    /// One account whose cookies are `cookies`, each archived under the name `NSHTTPCookie`.
    fileprivate func archive(_ cookies: ForgedCookie...) throws -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName("NSHTTPCookie", for: ForgedCookie.self)
        let entry = NSDictionary(dictionary: ["PSEUDO": "fakeuser1", "COOKIES": NSArray(array: cookies)])
        archiver.encode(NSArray(array: [entry]), forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        return archiver.encodedData
    }
}

/// A class no legacy archive holds (#1205), though it adopts `NSSecureCoding`: only the class list keeps it out, and its
/// decoder must never run.
@objc(HFRTestUnexpectedArchivedObject)
private final class UnexpectedArchivedObject: NSObject, NSSecureCoding {
    static let instantiated = Mutex(false)
    static var supportsSecureCoding: Bool { true }

    override init() {}

    init?(coder: NSCoder) {
        Self.instantiated.withLock { $0 = true }
    }

    func encode(with coder: NSCoder) {}
}

/// Archived under the name `NSHTTPCookie`, the way `NSHTTPCookie` archives itself (its properties as the unkeyed
/// object `$0`), with properties a test chooses.
@objc(HFRTestForgedCookie)
private final class ForgedCookie: NSObject, NSCoding {
    private let properties: NSDictionary

    init(_ properties: [String: Any]) {
        self.properties = NSDictionary(dictionary: properties)
    }

    init?(coder: NSCoder) { nil }

    func encode(with coder: NSCoder) {
        coder.encode(properties)
    }
}
#endif
