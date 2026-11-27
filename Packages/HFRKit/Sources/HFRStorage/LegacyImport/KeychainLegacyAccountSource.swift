#if canImport(Security)
import Foundation
import HFRModels
import Security

/// Reads the legacy Keychain item `HFR_COMPTES_KEY` (service = the bundle identifier), as `A0SimpleKeychain`
/// `dataForKey:` did (`A0SimpleKeychain.m:32, 87-110`, `baseQuery`, `queryFetchOneByKey:`). Read only: the item is
/// never written or deleted (LOT-067).
public struct KeychainLegacyAccountSource: LegacyAccountSource {
    /// `kSecAttrAccount` of the legacy item (`Constants.h:116`).
    public static let accountName = "HFR_COMPTES_KEY"

    /// `kSecAttrService` of the legacy item: the app's bundle identifier (`hfrplus.red.super`, Q-1).
    public let service: String

    /// Creates a source over the legacy item of `service`.
    public init(service: String) {
        self.service = service
    }

    public func accounts() throws(LegacyImportError) -> [LegacyAccountRecord] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw .sourceUnreadable }
            return try LegacyAccountArchive.decode(data)
        case errSecItemNotFound:
            return []
        default:
            // errSecInteractionNotAllowed (device locked before first unlock) and the like: retried at the next run.
            throw .sourceUnavailable
        }
    }
}
#endif

#if canImport(Darwin)
import Foundation
import HFRModels

/// Decodes the legacy account archive with `NSKeyedUnarchiver`, the API legacy read it with (`MultisManager.m:43-47`),
/// but with secure coding and a closed class list (#1205), where legacy's `unarchiveObjectWithData:` instantiated any
/// class the archive named.
///
/// `NSHTTPCookie` does not adopt `NSSecureCoding` (measured on macOS 27.2: a secure decode refuses it by name), so it is
/// never instantiated from the archive: its class name is mapped to `LegacyArchivedCookie`, which reads the one object
/// `NSHTTPCookie` archives (its properties dictionary, as the unkeyed object `$0`) under the same class list, and the
/// cookie is rebuilt with `HTTPCookie(properties:)` from the properties whose value types it expects.
public enum LegacyAccountArchive {
    /// Every class the legacy archive holds (`MultisManager.m:49-80`): the array of accounts, their dictionaries,
    /// strings, numbers, the avatar data, and a cookie's properties (strings, numbers, dates, arrays of ports; no URL:
    /// `NSHTTPCookie` archives `CommentURL` as a string and drops `OriginURL`, measured on macOS 27.2). Anything else
    /// fails the decode.
    static let allowedClasses: [AnyClass] = [
        NSArray.self, NSDictionary.self, NSString.self, NSNumber.self, NSData.self, NSDate.self,
        LegacyArchivedCookie.self
    ]

    /// The accounts of an archive; throws `sourceUnreadable` when it is not an array of dictionaries or names a class
    /// outside `allowedClasses`.
    public static func decode(_ data: Data) throws(LegacyImportError) -> [LegacyAccountRecord] {
        let root: Any?
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = true
            unarchiver.decodingFailurePolicy = .setErrorAndReturn
            unarchiver.setClass(LegacyArchivedCookie.self, forClassName: "NSHTTPCookie")
            root = unarchiver.decodeObject(of: allowedClasses, forKey: NSKeyedArchiveRootObjectKey)
            let failed = unarchiver.error != nil
            unarchiver.finishDecoding()
            guard !failed else { throw LegacyImportError.sourceUnreadable }
        } catch {
            throw .sourceUnreadable
        }
        guard let array = root as? [Any] else { throw .sourceUnreadable }
        return try array.map { item throws(LegacyImportError) in
            guard let entry = item as? [String: Any] else { throw .sourceUnreadable }
            return record(from: entry)
        }
    }

    private static func record(from entry: [String: Any]) -> LegacyAccountRecord {
        let cookies = (entry["COOKIES"] as? [Any] ?? []).compactMap { ($0 as? LegacyArchivedCookie)?.cookie.map(storedCookie) }
        return LegacyAccountRecord(
            pseudo: entry["PSEUDO"] as? String,
            displayName: entry["PSEUDO_DISPLAY"] as? String,
            cookies: cookies,
            hashCheck: entry["HASH"] as? String,
            avatarData: entry["AVATAR"] as? Data,
            isMain: (entry["MAIN"] as? NSNumber)?.boolValue ?? false
        )
    }

    private static func storedCookie(_ cookie: HTTPCookie) -> StoredCookie {
        StoredCookie(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
            path: cookie.path,
            expiresDate: cookie.expiresDate,
            isSecure: cookie.isSecure,
            isHTTPOnly: cookie.isHTTPOnly
        )
    }
}

/// Stands in for `NSHTTPCookie` while the legacy archive is decoded (`LegacyAccountArchive`): it keeps the properties
/// dictionary `NSHTTPCookie` archives as its unkeyed object `$0`, decoded under the unarchiver's class list.
@objc(HFRLegacyArchivedCookie)
final class LegacyArchivedCookie: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    private let properties: [String: Any]

    /// The cookie of those properties; nil when one has a value of a type `HTTPCookie(properties:)` does not take, or
    /// when Foundation cannot build a cookie from them. A key outside `verdict(on:forKey:)`'s list is dropped.
    var cookie: HTTPCookie? {
        var checked: [HTTPCookiePropertyKey: Any] = [:]
        for (key, value) in properties {
            switch Self.verdict(on: value, forKey: key) {
            case .keep: checked[HTTPCookiePropertyKey(key)] = value
            case .drop: continue
            case .refuse: return nil
            }
        }
        return HTTPCookie(properties: checked)
    }

    /// What `cookie` does with one archived property.
    enum PropertyVerdict { case keep, drop, refuse }

    /// `keep` when `value` has a type `HTTPCookie(properties:)` takes for `key`, `refuse` when not, `drop` for any other
    /// key. Foundation does not check them: a dictionary or a number under `Path`, `Comment`, `CommentURL`, `SameSite`
    /// or `StoragePartition` raises an Objective-C exception, a dictionary under `Port` crashes, the flags are read by
    /// presence, and a NaN `Expires` date reaches the cookie (measured on macOS 27.2, #1205). The keys are those
    /// `NSHTTPCookie` archives and those Apple documents, but `OriginURL`: it is never archived, and Foundation reads it
    /// for the domain of a cookie that has none, where some strings crash it (measured), so it is dropped and such a
    /// cookie skipped. The types are those it archives (strings; `Expires` a finite date, `Created` a number, `Port` an
    /// array of numbers) and those Apple documents, but a `CommentURL` URL, which raises. Dropping the other keys keeps
    /// a key Foundation reads but this list misses from reaching it unchecked.
    static func verdict(on value: Any, forKey key: String) -> PropertyVerdict {
        let expected: Bool
        switch key {
        case "Name", "Value", "Domain", "Path", "Comment", "CommentURL", "SameSite", "Secure", "HttpOnly",
            "Discard", "StoragePartition":
            expected = value is String
        case "Expires":
            expected = (value as? Date)?.timeIntervalSinceReferenceDate.isFinite == true || value is String
        case "Created":
            expected = value is NSNumber
        case "Version", "Max-Age":
            expected = value is String || value is NSNumber
        case "Port":
            expected = value is String || (value as? [Any])?.allSatisfy { $0 is NSNumber } == true
        default:
            return .drop
        }
        return expected ? .keep : .refuse
    }

    init?(coder: NSCoder) {
        // The unkeyed read is the only way to reach `$0` (a keyed read hides `$` keys); it keeps the unarchiver's
        // allowed classes, so a forged dictionary holding another class fails the whole decode.
        guard let properties = coder.decodeObject() as? [String: Any] else { return nil }
        self.properties = properties
    }

    func encode(with coder: NSCoder) {
        coder.encode(properties as NSDictionary)
    }
}
#endif
