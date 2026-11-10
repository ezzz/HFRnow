import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// The MP list's MPStorage flags (LOT-130): the legacy link, the `⚑ page / max` label, the opening at the flag.
@MainActor
struct MPStorageFlagTests {
    @Test func theLinkIsLegacysURLAsAForumPath() {
        let flag = MPStorageMPFlag(topic: 31, pValue: "1", href: "t555", page: 2)
        #expect(
            MPStorageFlagLink.path(of: flag) == "/forum2.php?config=hfr.inc&cat=prive&post=31&page=2&p=1&sondage=0&owntopic=0&trash=0"
                + "&trash_post=0&print=0&numreponse=0&quote_only=0&new=0&nojs=0#t555"
        )
    }

    @Test func valuesThatWouldChangeTheLinkAreNotCopied() throws {
        let flag = MPStorageMPFlag(topic: 31, pValue: "1&post=9", href: "t5&page=1", page: 2)
        let path = try #require(MPStorageFlagLink.path(of: flag))
        #expect(path.contains("&p=1&sondage"))
        #expect(!path.contains("#"))
        #expect(path.components(separatedBy: "&post=").count == 2)
    }

    @Test func aFlagWithoutPageHasNoLink() {
        #expect(MPStorageFlagLink.path(of: MPStorageMPFlag(topic: 31, href: "t555")) == nil)
        #expect(MPStorageFlagLink.path(of: MPStorageMPFlag(topic: 0, page: 2)) == nil)
    }

    @Test func aFlaggedGroupRowSaysWhereAndOpensThere() async throws {
        let text = try MPStorageSyncModelTests.flagged([MPStorageMPFlag(topic: 31, pValue: "1", href: "t555", page: 2)])
        let fixture = try await MPStorageSyncModelTests.make(
            thread: 7, state: .on, copy: MPStorageCopy(post: 7, base: text), text: text
        )
        await fixture.model.start()
        let list = MessageListModel(source: FakePrivateMessages(), mpStorage: fixture.model)
        let thread = messageThread(31, group: true, pages: 4)
        #expect(list.flagLabel(for: thread) == "⚑ 2 / 4")
        let reader = try #require(list.reader(for: thread))
        #expect(reader.requested.page == 2)
        #expect(reader.requested.anchor == 555)
        // A flag past the row's pages raises the maximum (`MPListView.swift:368`).
        #expect(list.flagLabel(for: messageThread(31, group: true, pages: 1)) == "⚑ 2 / 2")
    }

    @Test func withoutMPStorageTheRowOpensAtItsLatestMessage() async throws {
        let text = try MPStorageSyncModelTests.flagged([MPStorageMPFlag(topic: 31, pValue: "1", href: "t555", page: 2)])
        let fixture = try await MPStorageSyncModelTests.make(
            thread: 7, state: .on, copy: MPStorageCopy(post: 7, base: text), text: text
        )
        await fixture.model.start()
        await fixture.model.setEnabled(false)
        let list = MessageListModel(source: FakePrivateMessages(), mpStorage: fixture.model)
        let thread = messageThread(31, group: true, pages: 4)
        #expect(list.flagLabel(for: thread) == nil)
        #expect(try #require(list.reader(for: thread)).requested.page == 4)
    }
}
