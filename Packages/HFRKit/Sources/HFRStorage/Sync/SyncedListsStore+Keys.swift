import Foundation
import HFRModels

extension SyncedListsStore {
    // MARK: Keys

    /// The cloud key of an account's list, nil when the account key is empty, or when the account's longest key
    /// would exceed `maximumKeyLength`: an account syncs all its lists or none.
    func cloudKey(_ slot: Slot, account: String) -> String? {
        let accountKey = AccountKey.make(account)
        guard !accountKey.isEmpty else { return nil }
        let longest = Slot.allCases.map { $0.rawValue.utf8.count }.max() ?? 0
        guard longest + 1 + accountKey.utf8.count <= Self.maximumKeyLength else {
            unsyncedAccounts.insert(account)
            return nil
        }
        return "\(slot.rawValue).\(accountKey)"
    }

    func slot(of key: String) -> Slot {
        Slot(rawValue: String(key.prefix { $0 != "." })) ?? .allowlist
    }

    /// The quarantine key prefix of a list's digest.
    static let digestPrefix = "digest."
    /// A digest no list has: a list marked with it is taken as changed here.
    static let refusedDigest = "refused"

    static func isPositionsKey(_ key: String) -> Bool {
        key.hasPrefix("\(Slot.positions.rawValue).")
    }

    static func isListKey(_ key: String) -> Bool {
        key == allowlistKey || Slot.allCases.contains { $0 != .allowlist && key.hasPrefix("\($0.rawValue).") }
    }

    var cloudSchemaIsReadable: Bool {
        guard case .int(let version)? = cloud.value(forKey: SyncedSettingsStore.schemaVersionKey) else { return true }
        return version <= SyncedSettingsStore.schemaVersion
    }

    /// Topics and places of positions, dates left out.
    static func places(_ records: [ReadingPositionRecord]) -> Set<ReadingPositionRecord> {
        Set(records.map { record in
            var record = record
            record.position.updatedAt = .distantPast
            return record
        })
    }

    @discardableResult
    func schedule(_ event: Event, after delay: Duration) -> Task<Void, Never> {
        let sink = sink
        let sleep = sleep
        return Task {
            await sleep(delay)
            guard !Task.isCancelled else { return }
            sink.yield(event)
        }
    }
}
