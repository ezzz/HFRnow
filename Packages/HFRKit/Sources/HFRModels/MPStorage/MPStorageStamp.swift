import Foundation

/// Who writes and when: stamped into `sourceName` / `lastUpdate` at every level a change touches,
/// and used as the date of tombstones and new items. Also carries the tombstone write policy.
public struct MPStorageStamp: Sendable, Hashable {
    /// The `sourceName` the legacy iOS app writes (`MPStorage.m:26`).
    public static let legacySourceName = "iOS"

    /// Writer name, e.g. `iOS`.
    public var sourceName: String
    /// Instant of the change.
    public var date: Date
    /// Write policy: whether removals record new tombstones (and merges prune them). Off by default because
    /// no evidence yet shows that other writers keep the `tombstones` key (HFR-PROTOCOL §7); off, existing
    /// tombstones are still honoured and preserved, none is created.
    public var recordsTombstones: Bool

    /// Creates a stamp.
    public init(sourceName: String = MPStorageStamp.legacySourceName, date: Date, recordsTombstones: Bool = false) {
        self.sourceName = sourceName
        self.date = date
        self.recordsTombstones = recordsTombstones
    }
}
