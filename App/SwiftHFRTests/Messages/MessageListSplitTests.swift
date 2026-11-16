import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// "Deux listes" (LOT-171): the switch and the segment counts, on page 1 only (#968).
private func pageOf(_ threads: [PrivateMessageThread], page: Int, last: Int) -> PrivateMessageListPage {
    PrivateMessageListPage(
        threads: threads,
        navigation: PageNavigation(
            current: page, last: last, nextPath: page < last ? "/next" : nil, previousPath: page > 1 ? "/prev" : nil
        )
    )
}

// The suite limit is a backstop for a hang only: on a loaded simulator it measures the shared main-actor queue (#366).
@MainActor @Suite(.timeLimit(.minutes(5)))
struct MessageListSplitTests {
    private func model(
        _ source: FakePrivateMessages, display: MPListDisplay, store: (any SettingsStore)? = nil
    ) -> MessageListModel {
        let model = MessageListModel(source: source, isLoggedIn: { true }, settings: store)
        model.display = display
        return model
    }

    @Test func defaultShowsEveryRowOfTheListUnchanged() async {
        let source = FakePrivateMessages()
        let model = model(source, display: .single)
        await model.onAppear()
        #expect(model.visibleThreads == model.loader.value?.threads)
        #expect(model.visibleThreads.count == 2)
        #expect(source.requests == [1])
    }

    @Test func theSwitchShowsOnlyItsSegment() async {
        let source = FakePrivateMessages()
        let model = model(source, display: .split)
        await model.onAppear()
        #expect(model.visibleThreads.map(\.isGroup) == [false])
        model.select(.group)
        #expect(model.visibleThreads.map(\.isGroup) == [true])
        #expect(source.requests == [1])
    }

    @Test func eachSegmentCountsItsOwnUnreadRows() async {
        let source = FakePrivateMessages()
        source.handler = { _ in
            pageOf([messageThread(1, unread: true), messageThread(2, unread: true, group: true),
                    messageThread(3, unread: true, group: true), messageThread(4, group: true)], page: 1, last: 1)
        }
        let model = model(source, display: .split)
        await model.onAppear()
        #expect(model.unreadCount(in: .oneToOne) == 1)
        #expect(model.unreadCount(in: .group) == 2)
        // A conversation read here no longer counts.
        let opened = messageThread(2, unread: true, group: true)
        model.markOpened(opened, page: 1, of: 1)
        #expect(model.unreadCount(in: .group) == 1)
    }

    @Test func anEmptySegmentShowsEmptyAndNeverFetchesLaterPages() async {
        let source = FakePrivateMessages()
        // The group row sits on page 3: the list never asks for it.
        source.handler = { page in
            pageOf([messageThread(page)] + (page == 3 ? [messageThread(99, group: true)] : []), page: page, last: 4)
        }
        let model = model(source, display: .split)
        await model.onAppear()
        model.select(.group)
        #expect(source.requests == [1])
        #expect(model.visibleThreads.isEmpty)
    }

    @Test func switchingSegmentKeepsTheRowsAndTheirReadState() async {
        let source = FakePrivateMessages()
        let unread = messageThread(1, unread: true)
        source.handler = { page in pageOf([unread, messageThread(2, group: true)], page: page, last: 1) }
        let model = model(source, display: .split)
        await model.onAppear()
        model.markOpened(unread, page: 1, of: 1)
        model.select(.group)
        model.select(.oneToOne)
        #expect(!model.isUnread(unread))
        #expect(model.visibleThreads.map(\.id) == [unread.id])
        #expect(source.requests == [1])
    }

    @Test func aSentMessageReloadsPageOneAndShowsItsSegment() async {
        let source = FakePrivateMessages()
        // Page 1 holds only group rows; the sent one-to-one MP "Sujet 5" is on it too.
        source.handler = { page in
            pageOf([messageThread(1, group: true), messageThread(5)], page: page, last: 4)
        }
        let model = model(source, display: .split)
        await model.onAppear()
        model.select(.group)
        let before = source.requests
        await model.newMessageDidClose(.sent(newMessageConfirmed), subject: "Sujet 5")
        #expect(source.requests == before + [1])
        #expect(model.segment == .oneToOne)
        #expect(model.selected?.summary.topicID?.topic == 5)
        #expect(model.visibleThreads.contains { $0.id == model.selected?.id })
    }

    @Test func theSwitchIsHiddenWithoutRows() async {
        let source = FakePrivateMessages()
        let model = model(source, display: .split)
        #expect(!model.showsSegmentSwitch)
        await model.onAppear()
        #expect(model.showsSegmentSwitch)
        let signedOut = MessageListModel(source: source, isLoggedIn: { false })
        signedOut.display = .split
        await signedOut.onAppear()
        #expect(!signedOut.showsSegmentSwitch)
    }

    @Test func aConversationHiddenByTheSwitchIsClosed() async {
        let model = model(FakePrivateMessages(), display: .split)
        await model.onAppear()
        model.selected = messageThread(11, group: true)
        model.select(.oneToOne)
        #expect(model.selected == nil)
    }

    @Test func singleModeNeverFetchesMoreWhateverTheListHolds() async {
        let source = FakePrivateMessages()
        source.handler = { page in pageOf([messageThread(page)], page: page, last: 4) }
        let model = model(source, display: .single)
        await model.onAppear()
        model.select(.group)
        #expect(source.requests == [1])
    }

    @Test func theDisplaySettingIsReadWhenTheListAppears() async {
        let store = InMemorySettingsStore()
        let model = model(FakePrivateMessages(), display: .single, store: store)
        await model.onAppear()
        #expect(model.display == .single)
        store.set(.split, for: SettingKey.mpListDisplay)
        await model.onAppear()
        #expect(model.display == .split)
        #expect(model.visibleThreads.map(\.id) == [messageThread(10, unread: true).id])
    }

    @Test func theSegmentRulesFollowTheParsedGroupFlag() {
        #expect(MPSegment.group.contains(messageThread(1, group: true)))
        #expect(!MPSegment.group.contains(messageThread(1)))
        #expect(MPSegment.oneToOne.contains(messageThread(1)))
        #expect(!MPSegment.oneToOne.contains(messageThread(1, group: true)))
    }
}
