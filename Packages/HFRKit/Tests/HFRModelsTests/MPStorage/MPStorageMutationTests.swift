import Foundation
import Testing
@testable import HFRModels

@Suite struct MPStorageMutationTests {
    private typealias Fixtures = MPStorageFixtures

    @Test func addingABlockedPseudoInsertsFirstAndStampsEveryLevel() throws {
        var document = try Fixtures.document()
        let stamp = Fixtures.stamp(1_800_000_000)
        #expect(try document.addBlocklistEntry(username: "Spammer", stamp: stamp))

        let section = try #require(document.primary.blocklist)
        #expect(section.list.map(\.username) == ["Spammer", "Troll"])
        #expect(section.list.first?.createdAt == stamp.date)
        #expect(section.sourceName == "SwiftHFR" && section.lastUpdate == stamp.date)
        #expect(document.primary.sourceName == "SwiftHFR" && document.primary.lastUpdate == stamp.date)
        #expect(document.sourceName == "SwiftHFR" && document.lastUpdate == stamp.date)
        // Untouched sections keep the other writer's metadata.
        #expect(document.primary.bookmarks?.sourceName == "iOS")
    }

    @Test func blockingAnAlreadyListedPseudoIgnoresCaseAndChangesNothing() throws {
        var document = try Fixtures.document()
        let before = document
        #expect(try document.addBlocklistEntry(username: "tROLL", stamp: Fixtures.stamp(1_800_000_000)) == false)
        #expect(document == before)
    }

    @Test func unblockingRemovesEveryCaseVariantAndLeavesATombstone() throws {
        var document = try Fixtures.document()
        document.primary.blocklist?.list.append(MPStorageBlocklistEntry(username: "TROLL", createdAt: Date(timeIntervalSince1970: 1)))
        let stamp = Fixtures.recording(1_800_000_000)
        #expect(try document.removeBlocklistEntry(username: "troll", stamp: stamp))

        let section = try #require(document.primary.blocklist)
        #expect(section.list.isEmpty)
        #expect(section.tombstones == [MPStorageTombstone(id: "troll", deletedAt: stamp.date)])
        #expect(try document.removeBlocklistEntry(username: "troll", stamp: stamp) == false)
    }

    @Test func reAddingClearsTheTombstone() throws {
        var document = try Fixtures.document()
        try document.removeBlocklistEntry(username: "Troll", stamp: Fixtures.recording(1_800_000_000))
        try document.addBlocklistEntry(username: "Troll", stamp: Fixtures.stamp(1_800_000_100))
        #expect(document.primary.blocklist?.tombstones.isEmpty == true)
        #expect(document.primary.blocklist?.list.map(\.username) == ["Troll"])
    }

    @Test func bookmarksAreDatedDeduplicatedAndRemovedById() throws {
        var document = try Fixtures.document()
        let stamp = Fixtures.stamp(1_800_000_000)
        #expect(try document.addBookmark(Fixtures.bookmark(56, created: nil), stamp: stamp))
        #expect(document.primary.bookmarks?.list.first?.createdAt == stamp.date)
        // Same category, topic and message number: already bookmarked.
        #expect(try document.addBookmark(Fixtures.bookmark(56, label: "other"), stamp: stamp) == false)
        // Same message number in another category is another message (E18).
        var elsewhere = Fixtures.bookmark(56)
        elsewhere.category = "5"
        #expect(try document.addBookmark(elsewhere, stamp: stamp))

        #expect(try document.removeBookmark(id: "13-1711-55", stamp: Fixtures.recording(1_800_000_000)))
        #expect(document.primary.bookmarks?.list.map(\.id) == ["5-1711-56", "13-1711-56"])
        #expect(document.primary.bookmarks?.tombstones.map(\.id) == ["13-1711-55"])
    }

    @Test func upsertingAFlagReplacesItAndMovesItFirst() throws {
        var document = try Fixtures.document()
        let stamp = Fixtures.stamp(1_800_000_000)
        #expect(try document.upsertMPFlag(MPStorageMPFlag(topic: 9, page: 1), stamp: stamp))
        #expect(try document.upsertMPFlag(MPStorageMPFlag(topic: 123, page: 7), stamp: stamp))
        #expect(document.primary.mpFlags?.list.map(\.topic) == [123, 9])
        #expect(document.primary.mpFlags?.list.first?.page == 7)
        #expect(document.primary.mpFlags?.extra["active"] == .bool(true))
        // The same flag already first: nothing to write.
        #expect(try document.upsertMPFlag(MPStorageMPFlag(topic: 123, page: 7), stamp: stamp) == false)
    }

    @Test func removingAnUndatedFlagLeavesNoTombstone() throws {
        var document = try Fixtures.document()
        #expect(try document.removeMPFlag(topic: 123, stamp: Fixtures.stamp(1_800_000_000)))
        #expect(document.primary.mpFlags?.list.isEmpty == true)
        #expect(document.primary.mpFlags?.tombstones.isEmpty == true)
    }

    @Test func missingSectionsAreCreated() throws {
        var document = MPStorageDocument()
        try document.addBookmark(Fixtures.bookmark(1), stamp: Fixtures.stamp(1_800_000_000))
        #expect(document.primary.bookmarks?.list.count == 1)
        #expect(document.primary.blocklist == nil)
    }

    @Test(arguments: [
        #"{"data":[]}"#,
        #"{"data":[{"version":"0.2","bookmarks":{"list":[]}}]}"#
    ])
    func documentsWithoutAKnownEntryAreNeverEdited(json: String) throws {
        var document = try Fixtures.document(json)
        let before = document
        #expect(throws: MPStorageError.noWritableEntry) {
            try document.addBlocklistEntry(username: "x", stamp: Fixtures.stamp(1))
        }
        #expect(document == before)
    }

    @Test func theFirstVersion01EntryIsTheOneEdited() throws {
        var document = try Fixtures.document(#"{"data":[{"version":"0.2","x":1},{"version":"0.1"}]}"#)
        try document.addBlocklistEntry(username: "x", stamp: Fixtures.stamp(1))
        #expect(document.data[0].blocklist == nil)
        #expect(document.data[0].extra["x"] == .number(1))
        #expect(document.data[1].blocklist?.list.count == 1)
    }

    @Test(arguments: ["😀 smile", "ok\u{1F4A9}", "\u{10000}"])
    func textOutsideTheBasicMultilingualPlaneIsRefused(label: String) throws {
        var document = try Fixtures.document()
        let before = document
        #expect(throws: MPStorageError.self) {
            try document.addBookmark(Fixtures.bookmark(99, label: label), stamp: Fixtures.stamp(1))
        }
        #expect(throws: MPStorageError.self) {
            try document.addBlocklistEntry(username: label, stamp: Fixtures.stamp(1))
        }
        #expect(throws: MPStorageError.self) {
            try document.upsertMPFlag(MPStorageMPFlag(topic: 5, href: label), stamp: Fixtures.stamp(1))
        }
        #expect(document == before)
    }

    @Test func refusalNamesTheField() throws {
        var document = try Fixtures.document()
        let error = try #require(throws: MPStorageError.self) {
            try document.addBookmark(Fixtures.bookmark(99, label: "a😀"), stamp: Fixtures.stamp(1))
        }
        #expect(error == .nonBMPCharacter(path: ".bookmarks.list[0].label", codePoint: 0x1F600))
    }

    @Test func bmpTextIsAccepted() throws {
        var document = try Fixtures.document()
        #expect(try document.addBookmark(Fixtures.bookmark(99, label: "éàç ’ 漢字 \u{FFFD} \u{00A0}"), stamp: Fixtures.stamp(1)))
    }

    @Test func aForeignTombstonesKeyIsKeptAndNotWritten() throws {
        let json = #"{"data":[{"version":"0.1","bookmarks":{"list":[],"tombstones":"theirs"}}]}"#
        var document = try Fixtures.document(json)
        try document.addBookmark(Fixtures.bookmark(1), stamp: Fixtures.stamp(1_800_000_000))
        try document.removeBookmark(id: "13-1711-1", stamp: Fixtures.stamp(1_800_000_001))
        let section = try #require(document.primary.bookmarks)
        #expect(section.tombstones.isEmpty)
        #expect(section.extra["tombstones"] == .string("theirs"))
        let output = try MPStorageCodec.encodeForWriting(document)
        #expect(output.contains(#""tombstones":"theirs""#))
    }

    @Test func tombstonesArePrunedByAgeAndCount() throws {
        var document = MPStorageDocument()
        let start: TimeInterval = 1_800_000_000
        for index in 0..<60 {
            try document.addBookmark(Fixtures.bookmark(index, created: start), stamp: Fixtures.stamp(start))
        }
        for index in 0..<60 {
            try document.removeBookmark(id: "13-1711-\(index)", stamp: Fixtures.recording(start + Double(index)))
        }
        let tombstones = try #require(document.primary.bookmarks?.tombstones)
        #expect(tombstones.count == MPStorageTombstone.maximumPerSection)
        #expect(tombstones.first?.id == "13-1711-59")
        #expect(!tombstones.contains { $0.id == "13-1711-9" })

        // 90 days later, a new deletion drops the old ones.
        try document.addBookmark(Fixtures.bookmark(500, created: start), stamp: Fixtures.stamp(start))
        try document.removeBookmark(id: "13-1711-500", stamp: Fixtures.recording(start + MPStorageTombstone.retention + 100))
        #expect(document.primary.bookmarks?.tombstones.map(\.id) == ["13-1711-500"])
    }

    @Test func explicitPruningEditsOnlyTheWritableEntryAndStampsIt() throws {
        let old = MPStorageTombstone(id: "old", deletedAt: Date(timeIntervalSince1970: 1_000))
        let recent = MPStorageTombstone(id: "recent", deletedAt: Date(timeIntervalSince1970: 5_000))
        var document = MPStorageDocument(data: [
            MPStorageEntry(version: "0.2", bookmarks: MPStorageSection(tombstones: [old])),
            MPStorageEntry(bookmarks: MPStorageSection(tombstones: [old, recent]))
        ])
        let stamp = Fixtures.stamp(9_000)
        #expect(try document.pruneTombstones(before: Date(timeIntervalSince1970: 2_000), stamp: stamp))
        #expect(document.data[0].bookmarks?.tombstones == [old])
        #expect(document.data[1].bookmarks?.tombstones == [recent])
        #expect(document.data[1].bookmarks?.lastUpdate == stamp.date && document.lastUpdate == stamp.date)

        let before = document
        #expect(try document.pruneTombstones(before: Date(timeIntervalSince1970: 2_000), stamp: Fixtures.stamp(9_999)) == false)
        #expect(document == before)
    }

    @Test func explicitPruningNeedsAWritableEntry() throws {
        var document = try Fixtures.document(#"{"data":[{"version":"0.2"}]}"#)
        #expect(throws: MPStorageError.noWritableEntry) {
            try document.pruneTombstones(before: .now, stamp: Fixtures.stamp(1))
        }
    }

    @Test func byDefaultRemovalsRecordNoTombstoneAndWriteNoKey() throws {
        var document = try Fixtures.document()
        #expect(try document.removeBookmark(id: "13-1711-55", stamp: Fixtures.stamp(1_800_000_000)))
        #expect(try document.removeBlocklistEntry(username: "Troll", stamp: Fixtures.stamp(1_800_000_000)))
        #expect(document.primary.bookmarks?.tombstones.isEmpty == true)
        #expect(document.primary.blocklist?.tombstones.isEmpty == true)
        #expect(!(try MPStorageCodec.encodeForWriting(document)).contains("tombstones"))
    }

    @Test func upsertingAnIdenticalFlagThatIsNotFirstChangesNothing() throws {
        var document = try Fixtures.document()
        try document.upsertMPFlag(MPStorageMPFlag(topic: 9, page: 1), stamp: Fixtures.stamp(1_800_000_000))
        let before = document
        #expect(try document.upsertMPFlag(MPStorageMPFlag(topic: 123, pValue: "1", href: "/h", page: 4, uri: "/u"),
                                          stamp: Fixtures.stamp(1_800_000_001)) == false)
        #expect(document == before)
    }
}
