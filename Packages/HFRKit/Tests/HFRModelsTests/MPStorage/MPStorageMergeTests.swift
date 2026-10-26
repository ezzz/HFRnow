import Foundation
import Testing
@testable import HFRModels

@Suite struct MPStorageMergeTests {
    private typealias Fixtures = MPStorageFixtures
    private let late = Fixtures.stamp(1_860_000_000)

    /// Another client's write: legacy-style, only the root metadata changes (`MPStorage.m:259-262`).
    private func otherClient(_ base: MPStorageDocument, _ edit: (inout MPStorageEntry) -> Void) -> MPStorageDocument {
        var copy = base
        edit(&copy.primary)
        copy.sourceName = "DTCloud_GM"
        copy.lastUpdate = Date(timeIntervalSince1970: 1_850_000_000)
        return copy
    }

    @Test func nothingLocalMeansNothingToWrite() throws {
        let base = try Fixtures.document()
        let theirs = otherClient(base) { $0.extra["egoQuote"] = .object([:]) }
        let result = try MPStorageMerge.merge(base: base, ours: base, theirs: theirs, stamp: late)
        #expect(!result.needsWrite)
        #expect(result.document == theirs)
        #expect(result.conflicts.isEmpty)
    }

    @Test func concurrentAddsAreBothKeptOursFirst() throws {
        let base = try Fixtures.document()
        var ours = base
        try ours.addBookmark(Fixtures.bookmark(60), stamp: Fixtures.stamp(1_800_000_000))
        let theirs = otherClient(base) { $0.bookmarks?.list.insert(Fixtures.bookmark(61), at: 0) }

        let result = try MPStorageMerge.merge(base: base, ours: ours, theirs: theirs, stamp: late)
        #expect(result.needsWrite)
        #expect(result.document.primary.bookmarks?.list.map(\.numreponse) == [60, 61, 55])
        #expect(result.conflicts.isEmpty)
        #expect(result.document.primary.bookmarks?.sourceName == "SwiftHFR")
        #expect(result.document.primary.bookmarks?.lastUpdate == late.date)
        #expect(result.document.sourceName == "SwiftHFR" && result.document.primary.lastUpdate == late.date)
    }

    @Test func untouchedSectionsKeepTheirMetadata() throws {
        let base = try Fixtures.document()
        var ours = base
        try ours.addBlocklistEntry(username: "Spam", stamp: Fixtures.stamp(1_800_000_000))
        let theirs = otherClient(base) { $0.bookmarks?.list[0].label = "renamed" }
        let result = try MPStorageMerge.merge(base: base, ours: ours, theirs: theirs, stamp: late)
        #expect(result.document.primary.bookmarks == theirs.primary.bookmarks)
        #expect(result.document.primary.blocklist?.list.map(\.username) == ["Spam", "Troll"])
    }

    @Test func bothAddingTheSameItemDifferentlyKeepsOursAndReports() throws {
        let base = try Fixtures.document()
        var ours = base
        try ours.addBookmark(Fixtures.bookmark(60, label: "mine"), stamp: Fixtures.stamp(1_800_000_000))
        let theirs = otherClient(base) { $0.bookmarks?.list.insert(Fixtures.bookmark(60, label: "theirs"), at: 0) }
        let result = try MPStorageMerge.merge(base: base, ours: ours, theirs: theirs, stamp: late)
        #expect(result.document.primary.bookmarks?.list.first?.label == "mine")
        #expect(result.conflicts == [MPStorageConflict(location: "bookmarks", key: "13-1711-60", kind: .bothAdded, resolution: .keptOurs)])
    }

    @Test func deleteHereAgainstEditThereKeepsTheEdit() throws {
        let base = try Fixtures.document()
        var ours = base
        try ours.removeBookmark(id: "13-1711-55", stamp: Fixtures.stamp(1_800_000_000))
        let theirs = otherClient(base) { $0.bookmarks?.list[0].label = "edited" }
        let result = try MPStorageMerge.merge(base: base, ours: ours, theirs: theirs, stamp: late)
        let section = try #require(result.document.primary.bookmarks)
        #expect(section.list.map(\.label) == ["edited"])
        // The surviving item has no tombstone left, so a later merge cannot delete it again.
        #expect(section.tombstones.isEmpty)
        #expect(result.conflicts == [
            MPStorageConflict(location: "bookmarks", key: "13-1711-55", kind: .changedAndDeleted, resolution: .keptTheirs)
        ])
    }

    @Test func editHereAgainstDeleteThereKeepsTheEdit() throws {
        let base = try Fixtures.document()
        var ours = base
        try ours.upsertMPFlag(MPStorageMPFlag(topic: 123, page: 9), stamp: Fixtures.stamp(1_800_000_000))
        let theirs = otherClient(base) { $0.mpFlags?.list.removeAll() }
        let result = try MPStorageMerge.merge(base: base, ours: ours, theirs: theirs, stamp: late)
        #expect(result.document.primary.mpFlags?.list == [MPStorageMPFlag(topic: 123, page: 9)])
        #expect(result.document.primary.mpFlags?.extra["active"] == .bool(true))
        #expect(result.conflicts.map(\.kind) == [.changedAndDeleted])
    }

    @Test func unchangedItemsFollowTheOtherSidesDeletion() throws {
        let base = try Fixtures.document()
        // They delete the bookmark, we delete the blocked pseudo: both deletions apply.
        var ours = base
        try ours.removeBlocklistEntry(username: "Troll", stamp: Fixtures.recording(1_800_000_000))
        let theirs = otherClient(base) { $0.bookmarks?.list.removeAll() }
        let result = try MPStorageMerge.merge(base: base, ours: ours, theirs: theirs, stamp: late)
        #expect(result.document.primary.bookmarks?.list.isEmpty == true)
        #expect(result.document.primary.blocklist?.list.isEmpty == true)
        #expect(result.document.primary.blocklist?.tombstones.map(\.id) == ["troll"])
        #expect(result.conflicts.isEmpty)
    }

    @Test func bothChangingAnItemKeepsOurs() throws {
        let base = try Fixtures.document()
        var ours = base
        ours.primary.mpFlags?.list[0].page = 10
        let theirs = otherClient(base) { $0.mpFlags?.list[0].page = 11 }
        let result = try MPStorageMerge.merge(base: base, ours: ours, theirs: theirs, stamp: late)
        #expect(result.document.primary.mpFlags?.list.first?.page == 10)
        #expect(result.conflicts == [MPStorageConflict(location: "mpFlags", key: "123", kind: .bothChanged, resolution: .keptOurs)])
    }

    @Test func otherClientsNamespacesEntriesAndRootKeysArePreserved() throws {
        let base = try Fixtures.document()
        var ours = base
        try ours.addBlocklistEntry(username: "Spam", stamp: Fixtures.stamp(1_800_000_000))
        var theirs = otherClient(base) { entry in
            entry.extra["hfrChat"] = .object(["x": .array([.number(3)])])
            entry.extra["egoQuote"] = .object(["on": .bool(true)])
            entry.extra["superFavs"] = nil
        }
        theirs.extra["futureRootKey"] = .string("changed")
        theirs.data.append(MPStorageEntry(version: "0.2", extra: ["v2": .bool(true)]))

        let result = try MPStorageMerge.merge(base: base, ours: ours, theirs: theirs, stamp: late)
        let entry = result.document.primary
        #expect(entry.extra["hfrChat"] == .object(["x": .array([.number(3)])]))
        #expect(entry.extra["egoQuote"] == .object(["on": .bool(true)]))
        #expect(entry.extra["superFavs"] == nil)
        #expect(result.document.extra["futureRootKey"] == .string("changed"))
        #expect(result.document.data.count == 2 && result.document.data[1] == theirs.data[1])
        #expect(entry.blocklist?.list.map(\.username) == ["Spam", "Troll"])
        #expect(result.conflicts.isEmpty)
    }

    @Test func undecodableItemsOfOtherClientsAreKept() throws {
        let json = #"{"data":[{"version":"0.1","bookmarks":{"list":[{"weird":true}]}}]}"#
        let base = try Fixtures.document(json)
        var ours = base
        try ours.addBookmark(Fixtures.bookmark(1), stamp: Fixtures.stamp(1_800_000_000))
        var theirs = base
        theirs.primary.bookmarks?.undecodableItems.append(.string("another"))
        let result = try MPStorageMerge.merge(base: base, ours: ours, theirs: theirs, stamp: late)
        #expect(result.document.primary.bookmarks?.undecodableItems == [.object(["weird": .bool(true)]), .string("another")])
        #expect(result.document.primary.bookmarks?.list.count == 1)
    }

    @Test func withoutBaseADatedItemOlderThanATombstoneIsDeleted() throws {
        let base = try Fixtures.document()
        var theirs = base
        try theirs.removeBookmark(id: "13-1711-55", stamp: Fixtures.recording(1_855_000_000))
        // Our copy still has the bookmark (created before the deletion) and a newer one.
        var ours = base
        try ours.addBookmark(Fixtures.bookmark(70, created: 1_857_000_000), stamp: Fixtures.stamp(1_857_000_000))

        let result = try MPStorageMerge.merge(base: nil, ours: ours, theirs: theirs, stamp: late)
        #expect(result.document.primary.bookmarks?.list.map(\.numreponse) == [70])
        #expect(result.document.primary.bookmarks?.tombstones.map(\.id) == ["13-1711-55"])
    }

    @Test func withoutBaseAnItemCreatedAfterTheTombstoneSurvives() throws {
        let base = try Fixtures.document()
        var theirs = base
        try theirs.removeBookmark(id: "13-1711-55", stamp: Fixtures.recording(1_855_000_000))
        var ours = base
        ours.primary.bookmarks?.list[0].createdAt = Date(timeIntervalSince1970: 1_856_000_000)
        let result = try MPStorageMerge.merge(base: nil, ours: ours, theirs: theirs, stamp: late)
        #expect(result.document.primary.bookmarks?.list.map(\.numreponse) == [55])
        #expect(result.document.primary.bookmarks?.tombstones.isEmpty == true)
    }

    @Test func withoutBaseUndatedItemsAndDifferencesFavourTheForumCopy() throws {
        let base = try Fixtures.document()
        var ours = base
        ours.primary.mpFlags?.list[0].page = 99
        try ours.upsertMPFlag(MPStorageMPFlag(topic: 5), stamp: Fixtures.stamp(1_800_000_000))
        let theirs = base
        let result = try MPStorageMerge.merge(base: nil, ours: ours, theirs: theirs, stamp: late)
        #expect(result.document.primary.mpFlags?.list.map(\.topic) == [5, 123])
        #expect(result.document.primary.mpFlags?.list.last?.page == 4)
        #expect(result.conflicts == [
            MPStorageConflict(location: "mpFlags", key: "123", kind: .divergentWithoutBase, resolution: .keptTheirs)
        ])
    }

    @Test func tombstonesFromBothSidesAreUnitedKeepingTheLatest() throws {
        let base = try Fixtures.document()
        var ours = base
        ours.primary.blocklist?.tombstones = [MPStorageTombstone(id: "a", deletedAt: Date(timeIntervalSince1970: 1_858_000_000))]
        var theirs = base
        theirs.primary.blocklist?.tombstones = [
            MPStorageTombstone(id: "a", deletedAt: Date(timeIntervalSince1970: 1_859_000_000)),
            MPStorageTombstone(id: "b", deletedAt: Date(timeIntervalSince1970: 1_857_000_000))
        ]
        try ours.addBlocklistEntry(username: "Spam", stamp: Fixtures.stamp(1_800_000_000))
        let result = try MPStorageMerge.merge(base: base, ours: ours, theirs: theirs, stamp: late)
        let tombstones = try #require(result.document.primary.blocklist?.tombstones)
        #expect(tombstones.map(\.id) == ["a", "b"])
        #expect(tombstones.first?.deletedAt == Date(timeIntervalSince1970: 1_859_000_000))
    }

    @Test func sectionsAbsentOnTheForumAreCreatedFromOurs() throws {
        let base = try Fixtures.document(#"{"data":[{"version":"0.1"}]}"#)
        var ours = base
        try ours.addBookmark(Fixtures.bookmark(1), stamp: Fixtures.stamp(1_800_000_000))
        let result = try MPStorageMerge.merge(base: base, ours: ours, theirs: base, stamp: late)
        #expect(result.document.primary.bookmarks?.list.count == 1)
        #expect(result.needsWrite)
    }

    @Test func aForumCopyWithoutAKnownEntryIsRefused() throws {
        let ours = try Fixtures.document()
        let theirs = try Fixtures.document(#"{"data":[{"version":"0.2"}]}"#)
        #expect(throws: MPStorageError.noWritableEntry) {
            try MPStorageMerge.merge(base: ours, ours: ours, theirs: theirs, stamp: late)
        }
    }

    @Test func mergingIsStableWhenRepeated() throws {
        let base = try Fixtures.document()
        var ours = base
        try ours.addBookmark(Fixtures.bookmark(60), stamp: Fixtures.stamp(1_800_000_000))
        let theirs = otherClient(base) { $0.blocklist?.list.removeAll() }
        let first = try MPStorageMerge.merge(base: base, ours: ours, theirs: theirs, stamp: late)
        // After writing, the written copy is the new base and the forum copy: nothing more to do.
        let second = try MPStorageMerge.merge(base: first.document, ours: first.document, theirs: first.document, stamp: late)
        #expect(!second.needsWrite)
        #expect(try MPStorageCodec.decode(MPStorageCodec.encodeForWriting(first.document)) == first.document)
    }

    @Test func withThePolicyOffExistingTombstonesArePreservedNotCreatedNorPruned() throws {
        let old = MPStorageTombstone(id: "13-1-1", deletedAt: Date(timeIntervalSince1970: 1_000))
        var base = try Fixtures.document()
        base.primary.bookmarks?.tombstones = [old]
        var ours = base
        try ours.removeBookmark(id: "13-1711-55", stamp: Fixtures.stamp(1_800_000_000))
        let theirs = otherClient(base) { $0.blocklist?.list.removeAll() }
        let result = try MPStorageMerge.merge(base: base, ours: ours, theirs: theirs, stamp: late)
        #expect(result.document.primary.bookmarks?.list.isEmpty == true)
        #expect(result.document.primary.bookmarks?.tombstones == [old])
    }

    @Test func aFreshAddDroppedByANewerTombstoneIsReported() throws {
        let base = try Fixtures.document()
        var ours = base
        try ours.addBookmark(Fixtures.bookmark(80, created: 1_855_000_000), stamp: Fixtures.stamp(1_855_000_000))
        let theirs = otherClient(base) {
            $0.bookmarks?.tombstones = [MPStorageTombstone(id: "13-1711-80", deletedAt: Date(timeIntervalSince1970: 1_856_000_000))]
        }
        let result = try MPStorageMerge.merge(base: base, ours: ours, theirs: theirs, stamp: late)
        #expect(result.document.primary.bookmarks?.list.map(\.numreponse) == [55])
        #expect(result.conflicts == [
            MPStorageConflict(location: "bookmarks", key: "13-1711-80", kind: .addedAndDeleted, resolution: .deleted)
        ])
    }

    @Test func duplicateKeysCollapseToTheFirstOccurrence() throws {
        let base = try Fixtures.document()
        var ours = base
        try ours.addBlocklistEntry(username: "Spam", stamp: Fixtures.stamp(1_800_000_000))
        let theirs = otherClient(base) { $0.blocklist?.list.append(MPStorageBlocklistEntry(username: "TROLL")) }
        let result = try MPStorageMerge.merge(base: base, ours: ours, theirs: theirs, stamp: late)
        #expect(result.document.primary.blocklist?.list.map(\.username) == ["Spam", "Troll"])
    }

    @Test func theirsDroppingAWholeSectionKeepsOnlyOurNewItems() throws {
        let base = try Fixtures.document()
        var ours = base
        try ours.addBookmark(Fixtures.bookmark(90), stamp: Fixtures.stamp(1_800_000_000))
        let theirs = otherClient(base) { $0.bookmarks = nil }
        let result = try MPStorageMerge.merge(base: base, ours: ours, theirs: theirs, stamp: late)
        #expect(result.document.primary.bookmarks?.list.map(\.numreponse) == [90])

        // Untouched on our side, the section stays dropped.
        let untouched = try MPStorageMerge.merge(base: base, ours: base, theirs: theirs, stamp: late)
        #expect(untouched.document.primary.bookmarks == nil)
        #expect(!untouched.needsWrite)
    }

    @Test func aVersion01EntryAtAnotherIndexOnTheForumIsTheOneMerged() throws {
        let base = try Fixtures.document()
        var ours = base
        try ours.addBlocklistEntry(username: "Spam", stamp: Fixtures.stamp(1_800_000_000))
        var theirs = base
        theirs.data.insert(MPStorageEntry(version: "0.2", extra: ["v2": .bool(true)]), at: 0)
        let result = try MPStorageMerge.merge(base: base, ours: ours, theirs: theirs, stamp: late)
        #expect(result.document.data.count == 2)
        #expect(result.document.data[0] == theirs.data[0])
        #expect(result.document.data[1].blocklist?.list.map(\.username) == ["Spam", "Troll"])
    }
}
