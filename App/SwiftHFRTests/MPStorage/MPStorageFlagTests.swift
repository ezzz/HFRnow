import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// The MP list's MPStorage flags (LOT-130): the `⚑ page / max` label, and the opening that stays at the latest message
/// until SwiftHFR moves the flag itself.
@MainActor
struct MPStorageFlagTests {
    @Test func aFlaggedGroupRowSaysWhereButOpensAtItsLatestMessage() async throws {
        let text = try MPStorageSyncModelTests.flagged([MPStorageMPFlag(topic: 31, pValue: "1", href: "t555", page: 2)])
        let fixture = try await MPStorageSyncModelTests.make(
            thread: 7, state: .on, copy: MPStorageCopy(post: 7, base: text), text: text
        )
        await fixture.model.start()
        let list = MessageListModel(source: FakePrivateMessages(), mpStorage: fixture.model)
        let thread = messageThread(31, group: true, pages: 4)
        #expect(list.flagLabel(for: thread) == "⚑ 2 / 4")
        // A flag nobody moves would open an old page forever: the latest message, as without MPStorage.
        #expect(try #require(list.reader(for: thread)).requested.page == 4)
        // A flag past the row's pages raises the maximum (`MPListView.swift:368`).
        #expect(list.flagLabel(for: messageThread(31, group: true, pages: 1)) == "⚑ 2 / 2")
    }

    @Test func noLabelWithoutMPStorageOrWithoutAPage() async throws {
        let text = try MPStorageSyncModelTests.flagged([
            MPStorageMPFlag(topic: 31, pValue: "1", href: "t555", page: 2), MPStorageMPFlag(topic: 32, page: 0)
        ])
        let fixture = try await MPStorageSyncModelTests.make(
            thread: 7, state: .on, copy: MPStorageCopy(post: 7, base: text), text: text
        )
        await fixture.model.start()
        let list = MessageListModel(source: FakePrivateMessages(), mpStorage: fixture.model)
        #expect(list.flagLabel(for: messageThread(32, group: true, pages: 4)) == nil)
        await fixture.model.setEnabled(false)
        #expect(list.flagLabel(for: messageThread(31, group: true, pages: 4)) == nil)
    }
}
