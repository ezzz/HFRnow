import Foundation

/// Three-way merge of the MPStorage document (Q-6). `base` is the copy this app last read, `ours` is `base` plus
/// local edits, `theirs` is the copy just re-read from the forum before writing. Rules, documented in
/// `docs/lots/LOT-062-mpstorage-merge.md`:
/// - only the `0.1` entry is merged; other entries, root keys and namespaces this app does not model come from
///   `theirs` unless this app changed them;
/// - list items are matched by `storageKey`; a side that did not change an item since `base` takes the other
///   side's version; a change beats a concurrent deletion; on a real conflict this app's edit wins (it is the
///   last writer); a dated deletion (tombstone) removes a dated item created before it;
/// - without `base`, an item present on both sides keeps `theirs`, an item on one side only is kept unless a
///   tombstone on the other side is newer than its date;
/// - writer metadata changes only where the result differs from `theirs`.
public enum MPStorageMerge {
    /// Merges the three copies; throws `noWritableEntry` when `ours` or `theirs` has no `0.1` entry.
    public static func merge(
        base: MPStorageDocument?,
        ours: MPStorageDocument,
        theirs: MPStorageDocument,
        stamp: MPStorageStamp
    ) throws -> MPStorageMergeResult {
        guard let theirsIndex = theirs.writableEntryIndex, let oursIndex = ours.writableEntryIndex else {
            throw MPStorageError.noWritableEntry
        }
        var context = Context(baseKnown: base != nil, stamp: stamp)
        let baseEntry = base.map { document in
            document.writableEntryIndex.map { document.data[$0] } ?? MPStorageEntry(version: nil)
        }
        let theirsEntry = theirs.data[theirsIndex]
        let mergedEntry = context.mergeEntry(base: baseEntry, ours: ours.data[oursIndex], theirs: theirsEntry)
        let rootExtra = context.mergeValues(base: base?.extra, ours: ours.extra, theirs: theirs.extra, location: "root")

        guard mergedEntry != theirsEntry || rootExtra != theirs.extra else {
            return MPStorageMergeResult(document: theirs, conflicts: context.conflicts, needsWrite: false)
        }
        var merged = theirs
        merged.data[theirsIndex] = mergedEntry
        merged.extra = rootExtra
        merged.sourceName = stamp.sourceName
        merged.lastUpdate = stamp.date
        return MPStorageMergeResult(document: merged, conflicts: context.conflicts, needsWrite: true)
    }

    /// Decisions shared by every level of one merge.
    private struct Context {
        let baseKnown: Bool
        let stamp: MPStorageStamp
        var conflicts: [MPStorageConflict] = []

        mutating func mergeEntry(base: MPStorageEntry?, ours: MPStorageEntry, theirs: MPStorageEntry) -> MPStorageEntry {
            var merged = theirs
            merged.extra = mergeValues(base: base?.extra, ours: ours.extra, theirs: theirs.extra, location: "entry")
            merged.blocklist = mergeSection(base: base?.blocklist, ours: ours.blocklist, theirs: theirs.blocklist, location: "blacklist")
            merged.mpFlags = mergeSection(base: base?.mpFlags, ours: ours.mpFlags, theirs: theirs.mpFlags, location: "mpFlags")
            merged.bookmarks = mergeSection(base: base?.bookmarks, ours: ours.bookmarks, theirs: theirs.bookmarks, location: "bookmarks")
            if merged != theirs {
                merged.sourceName = stamp.sourceName
                merged.lastUpdate = stamp.date
            }
            return merged
        }

        /// Key-by-key merge of values this app does not model; `base` nil means unknown.
        mutating func mergeValues(
            base: [String: JSONValue]?,
            ours: [String: JSONValue],
            theirs: [String: JSONValue],
            location: String
        ) -> [String: JSONValue] {
            var result: [String: JSONValue] = [:]
            var keys = Set(ours.keys).union(theirs.keys)
            if let base { keys.formUnion(base.keys) }
            for key in keys.sorted() {
                let mine = ours[key], other = theirs[key]
                guard baseKnown else {
                    if let mine, let other, mine != other {
                        record(location, key, .divergentWithoutBase, .keptTheirs)
                    }
                    result[key] = other ?? mine
                    continue
                }
                let original = base?[key]
                if mine == original || mine == other {
                    result[key] = other
                } else if other == original {
                    result[key] = mine
                } else if mine == nil {
                    record(location, key, .changedAndDeleted, .keptTheirs)
                    result[key] = other
                } else {
                    record(location, key, other == nil ? .changedAndDeleted : .bothChanged, .keptOurs)
                    result[key] = mine
                }
            }
            return result
        }

        mutating func mergeSection<Item: MPStorageItem>(
            base: MPStorageSection<Item>?,
            ours: MPStorageSection<Item>?,
            theirs: MPStorageSection<Item>?,
            location: String
        ) -> MPStorageSection<Item>? {
            if ours == nil, theirs == nil { return nil }
            if baseKnown {
                if ours.sameContent(as: base) { return theirs }
                if theirs.sameContent(as: base) { return ours }
            }
            let empty = MPStorageSection<Item>()
            let mine = ours ?? empty, other = theirs ?? empty
            let original = baseKnown ? (base ?? empty) : nil

            var merged = other
            merged.list = mergeItems(base: original?.list, ours: mine, theirs: other, location: location)
            merged.undecodableItems = mergeRaw(
                base: original?.undecodableItems, ours: mine.undecodableItems, theirs: other.undecodableItems
            )
            merged.extra = mergeValues(base: original?.extra, ours: mine.extra, theirs: other.extra, location: location)
            let live = Set(merged.list.map(\.storageKey))
            merged.tombstones = merged.canRecordTombstones
                ? Self.latestTombstones(mine.tombstones + other.tombstones).filter { !live.contains($0.id) }
                : []
            if let theirs, merged.sameContent(as: theirs) { return theirs }
            // With the policy off, existing tombstones are kept as they are: neither created nor pruned.
            if stamp.recordsTombstones { merged.pruneExpiredTombstones(now: stamp.date) }
            merged.stamp(stamp)
            return merged
        }

        /// Item lists: items only this app has come first (as legacy inserts at the top), then `theirs` order.
        private mutating func mergeItems<Item: MPStorageItem>(
            base: [Item]?,
            ours: MPStorageSection<Item>,
            theirs: MPStorageSection<Item>,
            location: String
        ) -> [Item] {
            let originals = base.map(Self.firstByKey)
            let mine = Self.firstByKey(ours.list), other = Self.firstByKey(theirs.list)
            let oursDeleted = Self.deletionDates(ours.tombstones), theirsDeleted = Self.deletionDates(theirs.tombstones)
            let orderedKeys = Self.uniqueKeys(ours.list.filter { other[$0.storageKey] == nil } + theirs.list)
            var result: [Item] = []
            for key in orderedKeys {
                let copies = MPStorageItemCopies(original: originals?[key], mine: mine[key], other: other[key])
                let deletions = (ours: oursDeleted[key], theirs: theirsDeleted[key])
                if let decided = decide(key: key, copies: copies, deletions: deletions, location: location) {
                    result.append(decided)
                }
            }
            return result
        }

        private mutating func decide<Item: MPStorageItem>(
            key: String,
            copies: MPStorageItemCopies<Item>,
            deletions: (ours: Date?, theirs: Date?),
            location: String
        ) -> Item? {
            let original = copies.original
            switch (copies.mine, copies.other) {
            case let (mine?, other?):
                if mine == other { return mine }
                guard baseKnown else {
                    record(location, key, .divergentWithoutBase, .keptTheirs)
                    return other
                }
                if mine == original { return other }
                if other == original { return mine }
                record(location, key, original == nil ? .bothAdded : .bothChanged, .keptOurs)
                return mine
            case let (mine?, nil):
                return keepOneSided(mine, original: original, deletedOnOtherSide: deletions.theirs, side: .keptOurs, location: location)
            case let (nil, other?):
                return keepOneSided(other, original: original, deletedOnOtherSide: deletions.ours, side: .keptTheirs, location: location)
            case (nil, nil):
                return nil
            }
        }

        /// An item one side has and the other has not: deleted there, or added here.
        private mutating func keepOneSided<Item: MPStorageItem>(
            _ item: Item,
            original: Item?,
            deletedOnOtherSide deletion: Date?,
            side: MPStorageConflict.Resolution,
            location: String
        ) -> Item? {
            if baseKnown, let original {
                if item == original { return nil }
                record(location, item.storageKey, .changedAndDeleted, side)
                return item
            }
            if let deletion, let created = item.storageDate, deletion > created {
                // With a base this is a fresh add against a later deletion on the other side: worth reporting.
                if baseKnown { record(location, item.storageKey, .addedAndDeleted, .deleted) }
                return nil
            }
            return item
        }

        /// Raw undecodable items: never edited here, so `theirs` unless this app's copy dropped or added some.
        private func mergeRaw(base: [JSONValue]?, ours: [JSONValue], theirs: [JSONValue]) -> [JSONValue] {
            guard let base else { return theirs }
            let removed = base.filter { !ours.contains($0) }
            let added = ours.filter { !base.contains($0) && !theirs.contains($0) }
            return theirs.filter { !removed.contains($0) } + added
        }

        private mutating func record(
            _ location: String,
            _ key: String,
            _ kind: MPStorageConflict.Kind,
            _ resolution: MPStorageConflict.Resolution
        ) {
            conflicts.append(MPStorageConflict(location: location, key: key, kind: kind, resolution: resolution))
        }

        private static func firstByKey<Item: MPStorageItem>(_ items: [Item]) -> [String: Item] {
            var result: [String: Item] = [:]
            for item in items where result[item.storageKey] == nil { result[item.storageKey] = item }
            return result
        }

        private static func uniqueKeys<Item: MPStorageItem>(_ items: [Item]) -> [String] {
            var seen: Set<String> = []
            return items.map(\.storageKey).filter { seen.insert($0).inserted }
        }

        private static func deletionDates(_ tombstones: [MPStorageTombstone]) -> [String: Date] {
            tombstones.reduce(into: [:]) { dates, tombstone in
                dates[tombstone.id] = max(dates[tombstone.id] ?? tombstone.deletedAt, tombstone.deletedAt)
            }
        }

        /// One tombstone per id, the latest, newest first.
        private static func latestTombstones(_ tombstones: [MPStorageTombstone]) -> [MPStorageTombstone] {
            var latest: [String: MPStorageTombstone] = [:]
            for tombstone in tombstones where latest[tombstone.id].map({ $0.deletedAt < tombstone.deletedAt }) ?? true {
                latest[tombstone.id] = tombstone
            }
            return latest.values.sorted { ($0.deletedAt, $0.id) > ($1.deletedAt, $1.id) }
        }
    }
}

/// The three copies of one item during a merge.
private struct MPStorageItemCopies<Item: MPStorageItem> {
    let original: Item?
    let mine: Item?
    let other: Item?
}

extension MPStorageSection {
    /// Equality ignoring the writer metadata (`sourceName`, `lastUpdate`) and the order of tombstones.
    func sameContent(as other: MPStorageSection?) -> Bool {
        guard let other else { return false }
        return list == other.list && undecodableItems == other.undecodableItems
            && Set(tombstones) == Set(other.tombstones) && extra == other.extra
    }
}

extension Optional {
    /// `sameContent` lifted to optionals: two absent sections are the same.
    func sameContent<Item>(as other: MPStorageSection<Item>?) -> Bool where Wrapped == MPStorageSection<Item> {
        switch self {
        case nil: other == nil
        case let section?: section.sameContent(as: other)
        }
    }
}
