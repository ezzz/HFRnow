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
            pageOf([messageThread(page)] + (page == 1 ? [messageThread(90, group: true)] : []), page: page, last: 4)
        }
        let model = model(source, display: .split)
        await model.onAppear()
        await model.select(.group)
        await model.goToNextPage()
        let before = source.requests
        await model.goToPreviousPage()
        #expect(source.requests == before + [1])
        #expect(model.visibleThreads.map(\.isGroup) == [true])
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
        #expect(model.visibleThreads.allSatisfy { !$0.isGroup })
    }

    @Test func theSegmentRulesFollowTheParsedGroupFlag() {
        #expect(MPSegment.group.contains(messageThread(1, group: true)))
        #expect(!MPSegment.group.contains(messageThread(1)))
        #expect(MPSegment.oneToOne.contains(messageThread(1)))
        #expect(!MPSegment.oneToOne.contains(messageThread(1, group: true)))
    }
}
