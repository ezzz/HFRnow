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

/// Decodes the legacy account archive with `NSKeyedUnarchiver`, the API legacy read it with (`MultisManager.m:43-47`).
///
/// Insecure decoding, as legacy's `unarchiveObjectWithData:`: whether `NSHTTPCookie` decodes under secure coding is not
/// documented and is measured on a Mac (LOT-067 spec, M1). The input is only ever this app's own Keychain item.
public enum LegacyAccountArchive {
    /// The accounts of an archive; throws `sourceUnreadable` when it is not an array of dictionaries.
    public static func decode(_ data: Data) throws(LegacyImportError) -> [LegacyAccountRecord] {
        let root: Any?
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            unarchiver.decodingFailurePolicy = .setErrorAndReturn
            root = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
            unarchiver.finishDecoding()
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
        let cookies = (entry["COOKIES"] as? [Any] ?? []).compactMap { ($0 as? HTTPCookie).map(storedCookie) }
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
#endif
