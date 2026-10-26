import Foundation

/// Local edits of the document (legacy `MPStorage.m:230-310, 313-400, 463-525`). Each edit touches the `0.1`
/// entry only, stamps `sourceName`/`lastUpdate` on the section, the entry and the root, records a tombstone on
/// removal, and refuses text HFR cannot store. They return whether anything changed: no change, no write.
extension MPStorageDocument {
    /// Index of the entry this app reads and writes: the first one with version `0.1`.
    public var writableEntryIndex: Int? {
        data.firstIndex { $0.version == Self.schemaVersion }
    }

    /// Blocks a pseudo; false when it is already listed (case-insensitive, as legacy `MPStorage.m:250`).
    @discardableResult
    public mutating func addBlocklistEntry(username: String, stamp: MPStorageStamp) throws -> Bool {
        let entry = MPStorageBlocklistEntry(username: username, createdAt: stamp.date)
        return try insert(entry, into: \.blocklist, namespace: "blacklist", replacingExisting: false, stamp: stamp)
    }

    /// Unblocks a pseudo (every case variant); false when it was not listed.
    @discardableResult
    public mutating func removeBlocklistEntry(username: String, stamp: MPStorageStamp) throws -> Bool {
        let key = MPStorageBlocklistEntry(username: username).storageKey
        return try remove(key: key, from: \.blocklist, stamp: stamp)
    }

    /// Adds a bookmark, dated `stamp.date` when it has no date; false when the same message is already bookmarked.
    @discardableResult
    public mutating func addBookmark(_ bookmark: MPStorageBookmark, stamp: MPStorageStamp) throws -> Bool {
        var dated = bookmark
        dated.createdAt = bookmark.createdAt ?? stamp.date
        return try insert(dated, into: \.bookmarks, namespace: "bookmarks", replacingExisting: false, stamp: stamp)
    }

    /// Removes a bookmark by `MPStorageBookmark.id`; false when absent.
    @discardableResult
    public mutating func removeBookmark(id: String, stamp: MPStorageStamp) throws -> Bool {
        try remove(key: id, from: \.bookmarks, stamp: stamp)
    }

    /// Sets the read position of a conversation, replacing the previous one and moving it first (legacy
    /// `MPStorage.m:463-490`); false when that exact flag is already stored (legacy would move it first).
    @discardableResult
    public mutating func upsertMPFlag(_ flag: MPStorageMPFlag, stamp: MPStorageStamp) throws -> Bool {
        try insert(flag, into: \.mpFlags, namespace: "mpFlags", replacingExisting: true, stamp: stamp)
    }

    /// Removes the read position of a conversation; false when absent.
    @discardableResult
    public mutating func removeMPFlag(topic: Int, stamp: MPStorageStamp) throws -> Bool {
        try remove(key: String(topic), from: \.mpFlags, stamp: stamp)
    }

    /// Drops tombstones older than `date` and keeps at most `maximumPerSection` (the newest) in each section of
    /// the writable entry, stamping what changed like any other edit; false when nothing was pruned.
    @discardableResult
    public mutating func pruneTombstones(
        before date: Date,
        maximumPerSection: Int = MPStorageTombstone.maximumPerSection,
        stamp: MPStorageStamp
    ) throws -> Bool {
        guard let entryIndex = writableEntryIndex else { throw MPStorageError.noWritableEntry }
        let pruned = [
            prune(\.blocklist, at: entryIndex, before: date, maximum: maximumPerSection, stamp: stamp),
            prune(\.mpFlags, at: entryIndex, before: date, maximum: maximumPerSection, stamp: stamp),
            prune(\.bookmarks, at: entryIndex, before: date, maximum: maximumPerSection, stamp: stamp)
        ].contains(true)
        if pruned { stampEntry(at: entryIndex, stamp) }
        return pruned
    }

    private mutating func prune<Item: MPStorageItem>(
        _ keyPath: WritableKeyPath<MPStorageEntry, MPStorageSection<Item>?>,
        at entryIndex: Int,
        before date: Date,
        maximum: Int,
        stamp: MPStorageStamp
    ) -> Bool {
        guard var section = data[entryIndex][keyPath: keyPath] else { return false }
        let count = section.tombstones.count
        section.pruneTombstones(before: date, maximum: maximum)
        guard section.tombstones.count != count else { return false }
        section.stamp(stamp)
        data[entryIndex][keyPath: keyPath] = section
        return true
    }

    private mutating func insert<Item: MPStorageItem>(
        _ item: Item,
        into keyPath: WritableKeyPath<MPStorageEntry, MPStorageSection<Item>?>,
        namespace: String,
        replacingExisting: Bool,
        stamp: MPStorageStamp
    ) throws -> Bool {
        guard let entryIndex = writableEntryIndex else { throw MPStorageError.noWritableEntry }
        try MPStorageCodec.validateWritable(item, path: ".\(namespace).list[0]")
        var section = data[entryIndex][keyPath: keyPath] ?? MPStorageSection()
        let key = item.storageKey
        // Same content already stored once: no change. Moving it to the top alone would be a write the merge
        // cannot carry (it keeps the forum's order), so it is not one.
        if section.list.filter({ $0.storageKey == key }) == [item] { return false }
        if !replacingExisting, section.list.contains(where: { $0.storageKey == key }) { return false }
        section.list.removeAll { $0.storageKey == key }
        section.list.insert(item, at: 0)
        section.tombstones.removeAll { $0.id == key }
        section.stamp(stamp)
        data[entryIndex][keyPath: keyPath] = section
        stampEntry(at: entryIndex, stamp)
        return true
    }

    private mutating func remove<Item: MPStorageItem>(
        key: String,
        from keyPath: WritableKeyPath<MPStorageEntry, MPStorageSection<Item>?>,
        stamp: MPStorageStamp
    ) throws -> Bool {
        guard let entryIndex = writableEntryIndex else { throw MPStorageError.noWritableEntry }
        guard var section = data[entryIndex][keyPath: keyPath], section.list.contains(where: { $0.storageKey == key }) else {
            return false
        }
        // A tombstone only helps against a dated item (see MPStorageMerge); flags carry no date.
        let dated = section.list.contains { $0.storageKey == key && $0.storageDate != nil }
        section.list.removeAll { $0.storageKey == key }
        if dated, stamp.recordsTombstones { section.recordDeletion(of: key, at: stamp.date) }
        section.stamp(stamp)
        data[entryIndex][keyPath: keyPath] = section
        stampEntry(at: entryIndex, stamp)
        return true
    }

    mutating func stampEntry(at index: Int, _ stamp: MPStorageStamp) {
        data[index].sourceName = stamp.sourceName
        data[index].lastUpdate = stamp.date
        sourceName = stamp.sourceName
        lastUpdate = stamp.date
    }
}

extension MPStorageSection {
    /// Sets the writer metadata.
    mutating func stamp(_ stamp: MPStorageStamp) {
        sourceName = stamp.sourceName
        lastUpdate = stamp.date
    }

    /// Replaces any tombstone of `key` by one dated `date`, then prunes; no-op when another client owns the key.
    mutating func recordDeletion(of key: String, at date: Date) {
        guard canRecordTombstones else { return }
        tombstones.removeAll { $0.id == key }
        tombstones.insert(MPStorageTombstone(id: key, deletedAt: date), at: 0)
        pruneExpiredTombstones(now: date)
    }

    /// Applies the default retention and count limits relative to `now`.
    mutating func pruneExpiredTombstones(now: Date) {
        pruneTombstones(before: now.addingTimeInterval(-MPStorageTombstone.retention), maximum: MPStorageTombstone.maximumPerSection)
    }

    /// Drops tombstones older than `date`, then keeps the `maximum` newest.
    mutating func pruneTombstones(before date: Date, maximum: Int) {
        tombstones.removeAll { $0.deletedAt < date }
        if tombstones.count > maximum {
            tombstones.sort { $0.deletedAt > $1.deletedAt }
            tombstones.removeLast(tombstones.count - max(maximum, 0))
        }
    }
}
