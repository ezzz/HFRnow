import Foundation
import HFRClient
import HFRModels
import HFRParsing
import HFRStorage
@testable import SwiftHFR
import Testing

/// « MP multiples → dark topic » reads a group conversation like a public topic (#858): the position the reader reaches (the
/// app's own, and legacy's MPStorage flag when the storage is on), the `⚑ page / max` label, the opening there, and the row
/// kept unread until the last page. Nothing leaves the process: the forum side is `FakeMPStorageRemote`.
@MainActor
struct MPDarkTopicPositionTests {
    private typealias Base = MPStorageSyncModelTests

    private struct Fixture {
        let list: MessageListModel
        let storage: MPStorageSyncModelTests.Fixture
        let positions: MPReadingPositions
    }

    /// A list over an MP storage model in `state` (`.off`: the option works on the app's positions alone).
    private static func make(
        state: MPStorageSyncState = .off, text: String = FakeMPStorageRemote.emptyDocument, darkTopic: Bool = true
    ) async throws -> Fixture {
        let storage = try await Base.make(
            thread: 7, state: state, copy: MPStorageCopy(post: 7, base: text), text: text, darkTopic: darkTopic
        )
        await storage.model.start()
        let positions = MPReadingPositions(
            account: Base.account, store: ReadingPositionStore(persistence: InMemoryReadingPositionPersistence())
        )
        let list = MessageListModel(source: FakePrivateMessages(), mpStorage: storage.model, readingPositions: positions)
        return Fixture(list: list, storage: storage, positions: positions)
    }

    private static let conversation = TopicID(category: .privateMessages, topic: 31)

    // MARK: The app's own position (item 2), MP storage off

    @Test func aGroupLeftAtPage3Of12SaysWhereStaysUnreadAndReopensThere() async throws {
        let fixture = try await Self.make()
        let thread = messageThread(31, group: true, pages: 12)
        #expect(fixture.list.flagLabel(for: thread) == nil)
        await fixture.list.reached(MPReachedMessage(page: 1, lastMessage: 140), in: thread)
        await fixture.list.reached(MPReachedMessage(page: 3, lastMessage: 340), in: thread)
        #expect(fixture.list.flagLabel(for: thread) == "⚑ 3 / 12")
        #expect(fixture.list.isNotFullyRead(thread) && fixture.list.showsUnread(thread))
        // HFR's own state stays what it is: the badge and the counts do not move.
        #expect(!fixture.list.isUnread(thread))
        let reader = try #require(fixture.list.reader(for: thread))
        #expect(reader.requested.page == 3 && reader.requested.anchor == 340 && reader.requested.numreponse == nil)
        // Kept in the app, for the next launch.
        #expect(await fixture.positions.positions()[Self.conversation]?.messageNumber == 340)
        // Nothing for the forum: the storage is off.
        #expect(await fixture.storage.remote.calls.filter { $0 == .save }.isEmpty)
    }

    @Test func theLastPageClearsTheMarkAndANewPageBringsItBack() async throws {
        let fixture = try await Self.make()
        let thread = messageThread(31, group: true, pages: 12)
        await fixture.list.reached(MPReachedMessage(page: 12, lastMessage: 1200), in: thread)
        #expect(!fixture.list.isNotFullyRead(thread) && !fixture.list.showsUnread(thread))
        #expect(fixture.list.flagLabel(for: thread) == "⚑ 12 / 12")
        // Someone posted on a 13th page: the row is unread again.
        #expect(fixture.list.isNotFullyRead(messageThread(31, group: true, pages: 13)))
    }

    @Test func anEarlierPageNeverMovesThePositionBack() async throws {
        let fixture = try await Self.make()
        let thread = messageThread(31, group: true, pages: 12)
        await fixture.list.reached(MPReachedMessage(page: 5, lastMessage: 540), in: thread)
        await fixture.list.reached(MPReachedMessage(page: 2, lastMessage: 240), in: thread)
        #expect(fixture.list.flagLabel(for: thread) == "⚑ 5 / 12")
        #expect(await fixture.positions.positions()[Self.conversation]?.page == 5)
    }

    @Test func aPositionStoredElsewhereShowsAfterAReload() async throws {
        let fixture = try await Self.make()
        // Another window, or another device through iCloud (LOT-172), moved it.
        #expect(await fixture.positions.advance(Self.conversation, to: ReadingPosition(page: 4, messageNumber: 440)))
        await fixture.list.reloadPositions()
        #expect(fixture.list.flagLabel(for: messageThread(31, group: true, pages: 6)) == "⚑ 4 / 6")
    }

    @Test func withTheOptionOffNothingIsReadOrWritten() async throws {
        let fixture = try await Self.make(darkTopic: false)
        let thread = messageThread(31, group: true, pages: 12)
        await fixture.list.reached(MPReachedMessage(page: 3, lastMessage: 340), in: thread)
        #expect(await fixture.positions.positions().isEmpty)
        #expect(fixture.list.flagLabel(for: thread) == nil && !fixture.list.showsUnread(thread))
        // Legacy's opening: the latest message.
        #expect(try #require(fixture.list.reader(for: thread)).requested.page == 12)
    }

    @Test func aOneToOneConversationKeepsLegacysBehaviour() async throws {
        let fixture = try await Self.make(state: .on)
        let thread = messageThread(30, pages: 12)
        await fixture.list.reached(MPReachedMessage(page: 3, lastMessage: 340), in: thread)
        #expect(await fixture.positions.positions().isEmpty)
        #expect(fixture.storage.model.document.flatMap { MPStorageSync.flag(forThread: 30, in: $0) } == nil)
        #expect(fixture.list.flagLabel(for: thread) == nil && !fixture.list.showsUnread(thread))
        #expect(try #require(fixture.list.reader(for: thread)).requested.page == 12)
    }

    // MARK: Legacy's MPStorage flag (item 1), MP storage on

    @Test func withTheStorageOnTheFlagMovesLocallyAndIsSentOnceWhenTheConversationIsLeft() async throws {
        let fixture = try await Self.make(state: .on)
        let thread = messageThread(31, group: true, pages: 12)
        let savesBefore = await fixture.storage.remote.calls.filter { $0 == .save }.count
        fixture.list.selected = thread
        await fixture.list.reached(MPReachedMessage(page: 2, lastMessage: 240), in: thread)
        await fixture.list.reached(MPReachedMessage(page: 3, lastMessage: 340), in: thread)
        // In the device copy at once, nothing sent while reading.
        let flag = try #require(fixture.storage.model.document.flatMap { MPStorageSync.flag(forThread: 31, in: $0) })
        #expect(flag.page == 3 && flag.href == "t340" && flag.pValue == "1")
        #expect(await fixture.storage.remote.calls.filter { $0 == .save }.count == savesBefore)
        fixture.list.selected = nil
        await fixture.list.darkTopic.flagSend?.value
        #expect(await fixture.storage.remote.calls.filter { $0 == .save }.count == savesBefore + 1)
        let written = try MPStorageCodec.decode(await fixture.storage.remote.text)
        #expect(MPStorageSync.flag(forThread: 31, in: written)?.href == "t340")
        // Leaving again with nothing moved writes nothing.
        fixture.list.selected = thread
        fixture.list.selected = nil
        await fixture.list.darkTopic.flagSend?.value
        #expect(await fixture.storage.remote.calls.filter { $0 == .save }.count == savesBefore + 1)
    }

    @Test func aFlagAnotherClientMovedFurtherIsHonoured() async throws {
        let text = try Base.flagged([MPStorageMPFlag(topic: 31, pValue: "1", href: "t800", page: 8)])
        let fixture = try await Self.make(state: .on, text: text)
        let thread = messageThread(31, group: true, pages: 12)
        await fixture.list.reached(MPReachedMessage(page: 3, lastMessage: 340), in: thread)
        #expect(fixture.list.flagLabel(for: thread) == "⚑ 8 / 12")
        let reader = try #require(fixture.list.reader(for: thread))
        #expect(reader.requested.page == 8 && reader.requested.anchor == 800)
        // The flag is never moved back by an earlier page (legacy `pageToSave >= currentStoredPage`).
        #expect(fixture.storage.model.document.flatMap { MPStorageSync.flag(forThread: 31, in: $0) }?.page == 8)
    }

    // MARK: What the reader reached

    @Test func theReachedMessageIsThePagesLastOwnMessage() {
        let thread = messageThread(31, group: true, pages: 4)
        let messages = [Self.message(199, continuation: true), Self.message(201), Self.message(202)]
        let page = ReaderPage(topicID: Self.conversation, title: "Sujet", currentPage: 2, maxPage: 4, messages: messages)
        let topic = ReaderTarget.Source.topic(Self.conversation)
        #expect(MPReachedMessage(page: page, source: topic, of: thread) == MPReachedMessage(page: 2, lastMessage: 202))
        // Only the continuation block: nothing of this page was reached.
        let continuation = ReaderPage(
            topicID: Self.conversation, title: "Sujet", currentPage: 3, maxPage: 4, messages: [Self.message(202, continuation: true)]
        )
        #expect(MPReachedMessage(page: continuation, source: topic, of: thread) == nil)
        // Another conversation, or no page yet.
        #expect(MPReachedMessage(page: page, source: topic, of: messageThread(32, group: true, pages: 4)) == nil)
        #expect(MPReachedMessage(page: nil, source: topic, of: thread) == nil)
    }

    @Test func theQuoteViewReachesNothing() {
        let thread = messageThread(31, group: true, pages: 4)
        let page = ReaderPage(topicID: Self.conversation, title: "Sujet", currentPage: 1, maxPage: 1, messages: [Self.message(900)])
        let link = HFRQuotingLink(topic: Self.conversation, subcategory: nil, numreponse: 900)
        #expect(MPReachedMessage(page: page, source: .quotingMessages(link), of: thread) == nil)
    }

    private static func message(_ number: Int, continuation: Bool = false) -> ReaderMessage {
        ReaderMessage(
            numreponse: number, author: "user1", isDeleted: false, isContinuation: continuation, dateText: "",
            content: MessageContent(html: "<p>x</p>")
        )
    }
}
