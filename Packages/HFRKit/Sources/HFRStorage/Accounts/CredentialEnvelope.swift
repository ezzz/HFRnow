import Foundation
import HFRModels

/// The versioned, `Codable` form in which every store persists the accounts: `{"version":1,"accounts":[...]}`.
/// A version this code does not know is refused, never reinterpreted (E §5.2).
public enum CredentialEnvelope {
    /// Version written today.
    public static let currentVersion = 1

    private struct Probe: Decodable {
        let version: Int
    }

    private struct Payload: Codable {
        let version: Int
        let accounts: [Account]
    }

    /// Serializes the accounts in the current version.
    public static func encode(_ book: AccountBook) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Payload(version: currentVersion, accounts: book.accounts))
    }

    /// Reads an envelope. Errors are `CredentialStoreError` only: decoding errors are not forwarded, so no
    /// fragment of the stored secrets can reach a log through them.
    public static func decode(_ data: Data) throws -> AccountBook {
        let decoder = JSONDecoder()
        guard let probe = try? decoder.decode(Probe.self, from: data) else { throw CredentialStoreError.corrupted }
        guard probe.version >= 1 else { throw CredentialStoreError.corrupted }
        guard probe.version <= currentVersion else { throw CredentialStoreError.unsupportedVersion(probe.version) }
        guard let payload = try? decoder.decode(Payload.self, from: data) else { throw CredentialStoreError.corrupted }
        return AccountBook(accounts: payload.accounts)
    }
}
