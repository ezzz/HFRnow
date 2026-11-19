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
/// cookie is rebuilt with `HTTPCookie(properties:)`.
public enum LegacyAccountArchive {
    /// Every class the legacy archive holds (`MultisManager.m:49-80`): the array of accounts, their dictionaries,
    /// strings, numbers, the avatar data, and a cookie's properties (strings, numbers, dates, URLs, arrays of ports).
    /// Anything else fails the decode.
    static let allowedClasses: [AnyClass] = [
        NSArray.self, NSDictionary.self, NSString.self, NSNumber.self, NSData.self, NSDate.self, NSURL.self,
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

    /// The cookie of those properties; nil when Foundation cannot build one from them.
    var cookie: HTTPCookie? {
        HTTPCookie(properties: Dictionary(uniqueKeysWithValues: properties.map { (HTTPCookiePropertyKey($0.key), $0.value) }))
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
