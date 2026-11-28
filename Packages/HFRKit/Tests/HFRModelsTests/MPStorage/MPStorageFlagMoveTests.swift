import Foundation
import Testing
@testable import HFRModels

/// The flag a group conversation's reader writes (#858): legacy's shape (`MessagesView.swift:3582-3606` @ 87fe0d1c) and its
/// forward-only move (`pageToSave >= currentStoredPage`, `:3589-3590`).
@Suite struct MPStorageFlagMoveTests {
    private typealias Fixtures = MPStorageFixtures

    @Test func theReadFlagHasLegacysShape() {
        let flag = MPStorageMPFlag(conversation: 123, page: 3, lastMessage: 4567, pValue: "1")
        #expect(flag.topic == 123 && flag.page == 3 && flag.pValue == "1" && flag.href == "t4567")
        #expect(flag.uri == "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=prive&post=123&page=3&p=1&sondage=0"
            + "&owntopic=0&trash=0&trash_post=0&print=0&numreponse=0&quote_only=0&new=0&nojs=0#t4567")
        // Legacy writes "1" when the page gives no `p` (`nonEmptyString(…) ?? "1"`, `:3592`).
        #expect(MPStorageMPFlag(conversation: 123, page: 3, lastMessage: 4567, pValue: nil).pValue == "1")
        #expect(MPStorageMPFlag(conversation: 123, page: 3, lastMessage: 4567, pValue: "").pValue == "1")
    }

    @Test func theMessageOfAFlagIsItsTAnchor() {
        #expect(MPStorageMPFlag(topic: 1, href: "t555").messageNumber == 555)
        #expect(MPStorageMPFlag(topic: 1, href: "555").messageNumber == nil)
        #expect(MPStorageMPFlag(topic: 1, href: "t0").messageNumber == nil)
        #expect(MPStorageMPFlag(topic: 1, href: "bas").messageNumber == nil)
        #expect(MPStorageMPFlag(topic: 1).messageNumber == nil)
    }

    @Test func aFlagMovesForwardOrStaysOnItsPage() throws {
        var document = try Fixtures.document()
        // A conversation the fixture has no flag for.
        let stamp = Fixtures.stamp(1_800_000_000)
        #expect(try document.moveMPFlag(MPStorageMPFlag(conversation: 777, page: 3, lastMessage: 300, pValue: "1"), stamp: stamp))
        // An earlier page never moves it back.
        #expect(try document.moveMPFlag(MPStorageMPFlag(conversation: 777, page: 2, lastMessage: 200, pValue: "1"), stamp: stamp) == false)
        #expect(document.primary.mpFlags?.list.first { $0.topic == 777 }?.page == 3)
        // The same page again (new messages on it) moves it to its new last message.
        #expect(try document.moveMPFlag(MPStorageMPFlag(conversation: 777, page: 3, lastMessage: 310, pValue: "1"), stamp: stamp))
        #expect(document.primary.mpFlags?.list.first { $0.topic == 777 }?.href == "t310")
        // The same flag again is no change, so no write.
        #expect(try document.moveMPFlag(MPStorageMPFlag(conversation: 777, page: 3, lastMessage: 310, pValue: "1"), stamp: stamp) == false)
    }

    @Test func aFlagWithoutAPageIsOverwritten() throws {
        var document = try Fixtures.document()
        let stamp = Fixtures.stamp(1_800_000_000)
        try document.upsertMPFlag(MPStorageMPFlag(topic: 123, href: "t9"), stamp: stamp)
        // Legacy reads a missing page as -1 (`getPageFlagForTopidId:`, `MPStorage.m:547-563`), so any page moves it.
        #expect(try document.moveMPFlag(MPStorageMPFlag(conversation: 123, page: 1, lastMessage: 10, pValue: "1"), stamp: stamp))
    }

    @Test func movingKeepsWhatAnotherClientAddedToTheFlag() throws {
        var document = try Fixtures.document()
        let stamp = Fixtures.stamp(1_800_000_000)
        try document.upsertMPFlag(MPStorageMPFlag(topic: 123, page: 1, extra: ["seen": .string("x")]), stamp: stamp)
        #expect(try document.moveMPFlag(MPStorageMPFlag(conversation: 123, page: 2, lastMessage: 20, pValue: "1"), stamp: stamp))
        #expect(document.primary.mpFlags?.list.first { $0.topic == 123 }?.extra == ["seen": .string("x")])
    }

    // MARK: The merge keeps the further flag (#858, Fable round 1)

    /// The documents of one conversation's flag: base, ours and theirs at these pages and messages.
    private static func flagged(page: Int, message: Int) throws -> MPStorageDocument {
        var document = try Fixtures.document()
        let flag = MPStorageMPFlag(conversation: 777, page: page, lastMessage: message, pValue: "1")
        try document.upsertMPFlag(flag, stamp: Fixtures.stamp(1))
        return document
    }

    private static func mergedFlag(base: (Int, Int)?, ours: (Int, Int), theirs: (Int, Int)) throws -> MPStorageMPFlag? {
        let result = try MPStorageMerge.merge(
            base: try base.map { try flagged(page: $0.0, message: $0.1) }, ours: try flagged(page: ours.0, message: ours.1),
            theirs: try flagged(page: theirs.0, message: theirs.1), stamp: Fixtures.stamp(1_800_000_000)
        )
        return result.document.primary.mpFlags?.list.first { $0.topic == 777 }
    }

    /// Another client moved the flag to page 8 while this device's copy still said 2: the page 3 read here never moves it back.
    @Test func aConflictKeepsTheFurtherFlagWhicheverSideHasIt() throws {
        #expect(try Self.mergedFlag(base: (2, 200), ours: (3, 300), theirs: (8, 800))?.href == "t800")
        #expect(try Self.mergedFlag(base: (2, 200), ours: (8, 800), theirs: (3, 300))?.href == "t800")
        // Same page: the later message.
        #expect(try Self.mergedFlag(base: (2, 200), ours: (3, 310), theirs: (3, 305))?.href == "t310")
        #expect(try Self.mergedFlag(base: (2, 200), ours: (3, 305), theirs: (3, 310))?.href == "t310")
        // Without a base (first write of a copy), the further flag too.
        #expect(try Self.mergedFlag(base: nil, ours: (3, 300), theirs: (8, 800))?.href == "t800")
        #expect(try Self.mergedFlag(base: nil, ours: (8, 800), theirs: (3, 300))?.href == "t800")
    }

    /// The conflict is reported with the side kept.
    @Test func aFlagConflictIsReportedWithTheSideKept() throws {
        let result = try MPStorageMerge.merge(
            base: try Self.flagged(page: 2, message: 200), ours: try Self.flagged(page: 3, message: 300),
            theirs: try Self.flagged(page: 8, message: 800), stamp: Fixtures.stamp(1_800_000_000)
        )
        #expect(result.conflicts == [MPStorageConflict(location: "mpFlags", key: "777", kind: .bothChanged, resolution: .keptTheirs)])
        let unbased = try MPStorageMerge.merge(
            base: nil, ours: try Self.flagged(page: 8, message: 800), theirs: try Self.flagged(page: 3, message: 300),
            stamp: Fixtures.stamp(1_800_000_000)
        )
        #expect(unbased.conflicts == [
            MPStorageConflict(location: "mpFlags", key: "777", kind: .divergentWithoutBase, resolution: .keptOurs)
        ])
    }
}
