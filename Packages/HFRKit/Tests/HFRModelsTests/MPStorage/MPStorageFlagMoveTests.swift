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
}
