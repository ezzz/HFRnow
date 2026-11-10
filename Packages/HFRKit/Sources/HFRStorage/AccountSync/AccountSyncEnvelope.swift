import Foundation
import HFRModels

/// The dates this app keeps for one account, for the merge of the synchronizable copy (LOT-173).
public struct AccountStamp: Sendable, Hashable, Codable {
    /// Last change of the account's credentials on any device (login, re-login, refresh, avatar).
    public var credentialsAt: Date
    /// Last explicit login of the account on any device; a refresh never moves it.
    public var consentAt: Date

    /// Creates a stamp.
    public init(credentialsAt: Date, consentAt: Date) {
        self.credentialsAt = credentialsAt
        self.consentAt = consentAt
    }

    /// The stamp of an account stored before LOT-173 or by the legacy import: older than anything dated.
    public static let unknown = AccountStamp(credentialsAt: .distantPast, consentAt: .distantPast)
}

/// One account of the synchronizable copy with its dates.
public struct SyncedAccount: Sendable, Hashable, Codable {
    /// The account as the device-only item stores it.
    public var account: Account
    /// Last credentials change.
    public var credentialsAt: Date
    /// Last explicit login.
    public var consentAt: Date

    /// Creates an entry.
    public init(account: Account, stamp: AccountStamp) {
        self.account = account
        credentialsAt = stamp.credentialsAt
        consentAt = stamp.consentAt
    }

    /// The entry's dates.
    public var stamp: AccountStamp { AccountStamp(credentialsAt: credentialsAt, consentAt: consentAt) }
}

/// What the synchronizable Keychain item holds (ADR 0013 §6, LOT-173): a full envelope while sharing is on, or a dated
/// tombstone once a device switched it off. Version 1; a version this code does not know is refused, never rewritten.
public enum AccountSyncEnvelope: Sendable, Hashable {
    /// Sharing is on since `enabledAt`; `removed` holds per-account deletion markers by account key.
    case full(enabledAt: Date, accounts: [SyncedAccount], removed: [String: Date])
    /// Sharing was switched off at `deletedAt`; no credential.
    case tombstone(deletedAt: Date)

    /// Version written today.
    public static let currentVersion = 1

    /// `enabledAt` of a full envelope.
    public var enabledAt: Date? {
        if case .full(let enabledAt, _, _) = self { return enabledAt }
        return nil
    }

    /// `deletedAt` of a tombstone.
    public var deletedAt: Date? {
        if case .tombstone(let deletedAt) = self { return deletedAt }
        return nil
    }

    private struct Probe: Decodable {
        let version: Int
    }

    private struct Payload: Codable {
        let version: Int
        var enabledAt: Date?
        var updatedAt: Date?
        var deletedAt: Date?
        var accounts: [SyncedAccount]
        var removed: [String: Date]?
    }

    /// Serializes the envelope, keys sorted. `updatedAt` is the newest account or removal date (information only).
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload: Payload
        switch self {
        case .full(let enabledAt, let accounts, let removed):
            let dates = accounts.map(\.credentialsAt) + Array(removed.values)
            payload = Payload(
                version: Self.currentVersion, enabledAt: enabledAt, updatedAt: dates.max() ?? enabledAt,
                deletedAt: nil, accounts: accounts, removed: removed
            )
        case .tombstone(let deletedAt):
            payload = Payload(version: Self.currentVersion, deletedAt: deletedAt, accounts: [])
        }
        return try encoder.encode(payload)
    }

    /// Reads an envelope. Errors are `CredentialStoreError` only (no stored byte can reach a log): `corrupted` for
    /// anything unreadable, including an envelope that is both or neither full and tombstone, or a tombstone holding
    /// accounts; `unsupportedVersion` above version 1.
    public static func decode(_ data: Data) throws -> AccountSyncEnvelope {
        let decoder = JSONDecoder()
        guard let probe = try? decoder.decode(Probe.self, from: data) else { throw CredentialStoreError.corrupted }
        guard probe.version >= 1 else { throw CredentialStoreError.corrupted }
        guard probe.version <= currentVersion else { throw CredentialStoreError.unsupportedVersion(probe.version) }
        guard let payload = try? decoder.decode(Payload.self, from: data) else { throw CredentialStoreError.corrupted }
        switch (payload.enabledAt, payload.deletedAt) {
        case (let enabledAt?, nil):
            return .full(enabledAt: enabledAt, accounts: payload.accounts, removed: payload.removed ?? [:])
        case (nil, let deletedAt?) where payload.accounts.isEmpty:
            return .tombstone(deletedAt: deletedAt)
        default:
            throw CredentialStoreError.corrupted
        }
    }
}
