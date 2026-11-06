import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// "Deux listes" (LOT-171): the switch, the segment counts and the bounded search for a segment's rows.
private func pageOf(_ threads: [PrivateMessageThread], page: Int, last: Int) -> PrivateMessageListPage {
    PrivateMessageListPage(
        threads: threads,
        navigation: PageNavigation(
            current: page, last: last, nextPath: page < last ? "/next" : nil, previousPath: page > 1 ? "/prev" : nil
        )
    )
}

@MainActor
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
        await model.select(.group)
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

    @Test func anEmptySegmentLoadsLaterPagesInsteadOfShowingEmpty() async {
        let source = FakePrivateMessages()
        source.handler = { page in
            pageOf([messageThread(page * 10)] + (page == 3 ? [messageThread(99, group: true)] : []), page: page, last: 4)
        }
        let model = model(source, display: .split)
        await model.onAppear()
        await model.select(.group)
        #expect(source.requests == [1, 2, 3])
        #expect(model.visibleThreads.map(\.id) == [messageThread(99, group: true).id])
        #expect(model.currentPage == 3)
        #expect(!model.isSearchingSegment)
    }

    @Test func theSearchStopsAtTheLastPage() async {
        let source = FakePrivateMessages()
        source.handler = { page in pageOf([messageThread(page)], page: page, last: 2) }
        let model = model(source, display: .split)
        await model.onAppear()
        await model.select(.group)
        #expect(source.requests == [1, 2])
        #expect(model.visibleThreads.isEmpty)
        #expect(!model.canGoToNext)
    }

    @Test func theSearchIsBounded() async {
        let source = FakePrivateMessages()
        source.handler = { page in pageOf([messageThread(page)], page: page, last: 50) }
        let model = model(source, display: .split)
        await model.onAppear()
        await model.select(.group)
        #expect(source.requests == Array(1...(1 + MessageListModel.maxAutoAdvance)))
        #expect(model.visibleThreads.isEmpty)
        #expect(model.canGoToNext)
    }

    @Test func theSearchStopsOnAFailureAndKeepsTheRows() async {
        let source = FakePrivateMessages()
        source.handler = { page async throws(ListLoadError) -> PrivateMessageListPage in
            if page == 2 { throw ListLoadError.timedOut }
            return pageOf([messageThread(page)], page: page, last: 4)
        }
        let model = model(source, display: .split)
        await model.onAppear()
        await model.select(.group)
        #expect(source.requests == [1, 2])
        #expect(model.loader.error == .timedOut)
        #expect(model.loader.value?.page == 1)
    }

    @Test func goingBackNeverSearchesForward() async {
        let source = FakePrivateMessages()
        source.handler = { page in
            pageOf([messageThread(page)] + (page == 1 || page == 3 ? [messageThread(90 + page, group: true)] : []), page: page, last: 4)
        }
        let model = model(source, display: .split)
        await model.onAppear()
        await model.select(.group)
        await model.goToNextPage()
        // Page 2 has no group row: the next-page search moved on to page 3.
        #expect(model.currentPage == 3)
        let before = source.requests
        await model.goToPreviousPage()
        // The member asked for page 2: shown as it is (empty segment), not searched past.
        #expect(source.requests == before + [2])
        #expect(model.currentPage == 2)
        #expect(model.visibleThreads.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func switchingSegmentDuringASearchStopsIt() async {
        let source = FakePrivateMessages()
        let gate = Gate()
        source.handler = { page in
            if page == 2 { await gate.wait() }
            return pageOf([messageThread(page)], page: page, last: 4)
        }
        let model = model(source, display: .split)
        await model.onAppear()
        let search = Task { await model.select(.group) }
        await gate.waitUntilWaiting()
        #expect(model.isSearchingSegment)
        await model.select(.oneToOne)
        await gate.open()
        await search.value
        // Page 1 holds a one-to-one row: nothing is searched for it, and the search for the group stopped.
        #expect(source.requests == [1, 2])
        #expect(model.segment == .oneToOne)
        #expect(!model.isSearchingSegment)
        // The cancelled page-2 answer never reaches the screen.
        #expect(model.currentPage == 1)
        #expect(model.visibleThreads.map(\.id) == [messageThread(1).id])
    }

    @Test(.timeLimit(.minutes(1)))
    func aCancelledSearchDoesNotUndoWhatWasReadMeanwhile() async {
        let source = FakePrivateMessages()
        let gate = Gate()
        let unread = messageThread(1, unread: true)
        source.handler = { page in
            if page == 2 { await gate.wait() }
            return pageOf([page == 1 ? unread : messageThread(page)], page: page, last: 4)
        }
        let model = model(source, display: .split)
        await model.onAppear()
        model.markOpened(unread, page: 1, of: 1)
        #expect(!model.isUnread(unread))
        // The group search is on page 2 when the member switches back.
        let search = Task { await model.select(.group) }
        await gate.waitUntilWaiting()
        await model.select(.oneToOne)
        await gate.open()
        await search.value
        #expect(model.currentPage == 1)
        #expect(!model.isUnread(unread))
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
        await model.select(.oneToOne)
        #expect(model.selected == nil)
    }

    @Test func singleModeNeverSearchesWhateverTheListHolds() async {
        let source = FakePrivateMessages()
        source.handler = { page in pageOf([messageThread(page)], page: page, last: 4) }
        let model = model(source, display: .single)
        await model.onAppear()
        await model.select(.group)
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

/// Holds a fake source's answer until the test opens it, with no wall-clock wait.
private actor Gate {
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiter = continuation
            observers.forEach { $0.resume() }
            observers = []
        }
    }

    /// Returns once a caller is parked in `wait()`.
    func waitUntilWaiting() async {
        if waiter != nil { return }
        await withCheckedContinuation { observers.append($0) }
    }

    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }
}
