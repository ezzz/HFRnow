import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// The Messages list at 100 conversations per screen (#968): screen n is HFR's pages 2n - 1 and 2n merged.
struct ScreenedPrivateMessageSourceTests {
    /// An HFR page of the MP list with the given thread numbers, `last` pages in all.
    private func hfrPage(_ page: Int, last: Int, threads: [Int]) -> PrivateMessageListPage {
        PrivateMessageListPage(
            threads: threads.map { messageThread($0) },
            navigation: PageNavigation(
                current: page, last: last, nextPath: page < last ? "/next" : nil, previousPath: page > 1 ? "/prev" : nil
            ),
            newMessagePath: page == 1 ? "/new" : nil
        )
    }

    /// A mailbox of `last` HFR pages, each holding two threads numbered from `page * 10`.
    private func mailbox(last: Int) -> FakePrivateMessages {
        let source = FakePrivateMessages()
        source.handler = { page in self.hfrPage(page, last: last, threads: [page * 10, page * 10 + 1]) }
        return source
    }

    @Test func screenOneIsHFRPagesOneAndTwoMergedInOrder() async throws {
        let base = mailbox(last: 5)
        let screen = try await ScreenedPrivateMessageSource(base: base).privateMessages(page: 1)
        #expect(base.requests == [1, 2])
        #expect(screen.threads.map { $0.summary.topicID?.topic } == [10, 11, 20, 21])
        #expect(screen.navigation.current == 1 && screen.navigation.nextPath != nil && screen.navigation.previousPath == nil)
        #expect(screen.newMessagePath == "/new")
    }

    @Test func screenTwoIsPagesThreeAndFour() async throws {
        let base = mailbox(last: 5)
        let screen = try await ScreenedPrivateMessageSource(base: base).privateMessages(page: 2)
        #expect(base.requests == [3, 4])
        #expect(screen.threads.map { $0.summary.topicID?.topic } == [30, 31, 40, 41])
        #expect(screen.navigation.previousPath != nil && screen.navigation.nextPath != nil)
    }

    @Test func theCountOfScreensIsHalfTheLastHFRPageRoundedUp() async throws {
        #expect(ScreenedPrivateMessageSource.screenCount(lastHFRPage: 1) == 1)
        #expect(ScreenedPrivateMessageSource.screenCount(lastHFRPage: 2) == 1)
        #expect(ScreenedPrivateMessageSource.screenCount(lastHFRPage: 3) == 2)
        #expect(ScreenedPrivateMessageSource.screenCount(lastHFRPage: 5) == 3)
        let screen = try await ScreenedPrivateMessageSource(base: mailbox(last: 5)).privateMessages(page: 1)
        #expect(screen.navigation.last == 3)
    }

    @Test func theLastScreenOfAnOddMailboxHasOnePageAndNoNext() async throws {
        let base = mailbox(last: 5)
        let screen = try await ScreenedPrivateMessageSource(base: base).privateMessages(page: 3)
        #expect(base.requests == [5])
        #expect(screen.threads.count == 2)
        #expect(screen.navigation.nextPath == nil && screen.navigation.last == 3)
    }

    @Test func aSinglePageMailboxIsOneRequestAndOneScreen() async throws {
        let base = mailbox(last: 1)
        let screen = try await ScreenedPrivateMessageSource(base: base).privateMessages(page: 1)
        #expect(base.requests == [1])
        #expect(screen.navigation.last == 1 && screen.navigation.nextPath == nil)
    }

    @Test func aConversationThatMovedBetweenTheTwoRequestsShowsOnce() async throws {
        let base = FakePrivateMessages()
        base.handler = { page in
            self.hfrPage(page, last: 2, threads: page == 1 ? [1, 2, 3] : [3, 4])
        }
        let screen = try await ScreenedPrivateMessageSource(base: base).privateMessages(page: 1)
        #expect(screen.threads.map { $0.summary.topicID?.topic } == [1, 2, 3, 4])
    }

    @Test func aFailureOfTheSecondPageFailsTheScreen() async {
        let base = FakePrivateMessages()
        base.handler = { page async throws(ListLoadError) -> PrivateMessageListPage in
            if page == 2 { throw ListLoadError.timedOut }
            return self.hfrPage(page, last: 4, threads: [page])
        }
        await #expect(throws: ListLoadError.self) {
            try await ScreenedPrivateMessageSource(base: base).privateMessages(page: 1)
        }
    }

    @MainActor
    @Test func theModelPagesByScreensAndKnowsTheirCount() async {
        let base = mailbox(last: 5)
        let model = MessageListModel(source: ScreenedPrivateMessageSource(base: base), isLoggedIn: { true })
        await model.onAppear()
        #expect(model.pageCount == 3 && model.currentPage == 1 && model.canGoToNext && !model.canGoToPrevious)
        await model.goToNextPage()
        await model.goToNextPage()
        #expect(model.currentPage == 3 && !model.canGoToNext && model.canGoToPrevious)
        #expect(base.requests == [1, 2, 3, 4, 5])
    }
}
