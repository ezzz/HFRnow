import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// The reader's loading rules: E25 (one fetch per page the user opens), issues #106, #107 and #108.
@MainActor
struct TopicReaderModelTests {
    private func model(_ pages: FakeTopicPages, page: Int = 1, anchor: Int? = nil) -> TopicReaderModel {
        TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic), page: page, anchor: anchor), title: "Sujet", source: pages)
    }

    @Test func thePageTheUserOpensIsFetchedExactlyOnce() async {
        let pages = FakeTopicPages()
        let reader = model(pages)
        let gate = ReaderGate()
        pages.handler = { target in await gate.wait(); return readerPage(page: target.page) }
        let first = Task { await reader.onAppear() }
        await gate.untilArrived()
        await reader.onAppear() // the view appears again while the load runs
        await gate.open()
        await first.value
        await reader.onAppear() // and again once loaded (rotation, column change)
        #expect(pages.requests == [ReaderTarget(source: .topic(readerTopic), page: 1)])
        #expect(reader.page?.currentPage == 1)
        #expect(reader.document?.token == 1)
    }

    @Test func refreshReloadsThePageOnScreenAndKeepsItWhileLoading() async {
        let pages = FakeTopicPages()
        let reader = model(pages, page: 3, anchor: 301)
        await reader.onAppear()
        let gate = ReaderGate()
        pages.handler = { target in await gate.wait(); return readerPage(page: target.page) }
        let refresh = Task { await reader.refresh() }
        await gate.untilArrived()
        #expect(reader.page?.currentPage == 3)
        #expect(reader.isLoading)
        await gate.open()
        await refresh.value
        #expect(pages.requests.map(\.page) == [3, 3])
        #expect(pages.requests.last?.anchor == nil)
        #expect(reader.document?.keepsScrollPosition == true)
        #expect(reader.document?.token == 2)
    }

    @Test func aFailedRefreshKeepsTheContentAndReportsTheError() async {
        let pages = FakeTopicPages()
        let reader = model(pages, page: 2)
        await reader.onAppear()
        let document = reader.document
        pages.handler = { (_) async throws(ListLoadError) -> ReaderPage in throw .timedOut }
        await reader.refresh()
        #expect(reader.page?.currentPage == 2)
        #expect(reader.document == document)
        #expect(reader.error == .timedOut)
        pages.handler = { target in readerPage(page: target.page) }
        await reader.refresh()
        #expect(reader.error == nil)
        #expect(pages.requests.map(\.page) == [2, 2, 2])
    }

    @Test func aFailedPageChangeKeepsThePageAndRetryAsksForTheTarget() async {
        let pages = FakeTopicPages()
        let reader = model(pages)
        await reader.onAppear()
        pages.handler = { (_) async throws(ListLoadError) -> ReaderPage in throw .offline }
        await reader.goToPage(4)
        #expect(reader.page?.currentPage == 1)
        pages.handler = { target in readerPage(page: target.page) }
        await reader.refresh()
        #expect(reader.page?.currentPage == 1)
        await reader.goToPage(4)
        pages.handler = { (_) async throws(ListLoadError) -> ReaderPage in throw .offline }
        await reader.goToPage(5)
        pages.handler = { target in readerPage(page: target.page) }
        await reader.retry()
        #expect(reader.page?.currentPage == 5)
        #expect(pages.requests.map(\.page) == [1, 4, 1, 4, 5, 5])
    }

    @Test func aSupersededLoadNeverDelivers() async {
        let pages = FakeTopicPages()
        let reader = model(pages)
        await reader.onAppear()
        let gate = ReaderGate()
        pages.handler = { target in
            if target.page == 2 { await gate.wait() }
            return readerPage(page: target.page)
        }
        let slow = Task { await reader.goToPage(2) }
        await gate.untilArrived()
        await reader.goToPage(3)
        await gate.open()
        await slow.value
        #expect(reader.page?.currentPage == 3)
        #expect(reader.document?.token == 2)
        #expect(!reader.isLoading)
    }

    @Test func aCancelledLoadNeverDelivers() async {
        let pages = FakeTopicPages()
        let reader = model(pages)
        let gate = ReaderGate()
        pages.handler = { target in await gate.wait(); return readerPage(page: target.page) }
        let load = Task { await reader.onAppear() }
        await gate.untilArrived()
        reader.cancel()
        await gate.open()
        await load.value
        #expect(reader.page == nil)
        #expect(reader.document == nil)
        #expect(reader.error == nil)
    }

    @Test func onlyTheCurrentDocumentCanBecomeReady() async {
        let pages = FakeTopicPages()
        let reader = model(pages)
        await reader.onAppear()
        await reader.goToPage(2)
        reader.documentDidBecomeReady(token: 1)
        #expect(!reader.hasShownDocument)
        reader.documentDidBecomeReady(token: 2)
        #expect(reader.hasShownDocument)
        #expect(reader.readyToken == 2)
    }

    @Test func theDocumentScrollsToTheAnchorOnlyWhenThePostIsOnThePage() async {
        let pages = FakeTopicPages()
        let reader = model(pages, page: 2, anchor: 201)
        await reader.onAppear()
        #expect(reader.document?.anchor == 201)
        await reader.open(ReaderTarget(source: .topic(readerTopic), page: 4, anchor: 999))
        #expect(reader.document?.anchor == nil)
    }

    @Test func aPostLinkOnThePageShownScrollsWithoutRefetching() async {
        let pages = FakeTopicPages()
        let reader = model(pages, page: 2)
        await reader.onAppear()
        await reader.open(ReaderTarget(source: .topic(readerTopic), page: 2, anchor: 201))
        #expect(pages.requests.count == 1)
        #expect(reader.scrollRequest?.anchor == 201)
        #expect(reader.scrollRequest?.token == reader.document?.token)
        await reader.open(ReaderTarget(source: .topic(readerTopic), page: 3, anchor: 301))
        #expect(pages.requests.last == ReaderTarget(source: .topic(readerTopic), page: 3, anchor: 301))
        #expect(reader.document?.anchor == 301)
    }

    @Test func thePageServedWinsOverThePageAsked() async {
        let pages = FakeTopicPages { _ in readerPage(page: 5) }
        let reader = model(pages, page: 99)
        await reader.onAppear()
        await reader.refresh()
        #expect(pages.requests.map(\.page) == [99, 5])
        #expect(!reader.canGoToNext)
        #expect(reader.canGoToPrevious)
    }

    @Test func pageNumbersAreClamped() async {
        let pages = FakeTopicPages()
        let reader = model(pages)
        await reader.onAppear()
        await reader.goToPage(42)
        await reader.goToPage(-3)
        #expect(pages.requests.map(\.page) == [1, 5, 1])
    }

    @Test func linksOpenInTheReaderOrOutside() async {
        let pages = FakeTopicPages()
        let reader = model(pages)
        await reader.onAppear()
        let post = url("https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_4.htm#t401")
        #expect(reader.action(forLink: post) == .reader(ReaderTarget(source: .topic(readerTopic), page: 4, anchor: 401)))
        #expect(reader.action(forLink: url("https://example.com/a")) == .external(url("https://example.com/a")))
        let logout = url("https://forum.hardware.fr/user/logout.php")
        #expect(reader.action(forLink: logout) == .external(logout))
        #expect(reader.action(forLink: url("mailto:someone@example.com")) == .ignored)
    }

    @Test func aVideoIsFoundOnlyInTheCurrentDocument() async {
        let embed = MessageEmbed(
            provider: .vimeo, sourceURL: url("https://vimeo.com/1"), embedURL: url("https://player.vimeo.com/video/1")
        )
        let pages = FakeTopicPages { target in
            var page = readerPage(page: target.page)
            page.messages[0].content.embeds = [embed]
            return page
        }
        let reader = model(pages)
        await reader.onAppear()
        let token = reader.document?.token ?? 0
        #expect(reader.video(post: 100, index: 0, token: token) == embed)
        #expect(reader.video(post: 100, index: 1, token: token) == nil)
        #expect(reader.video(post: 100, index: 0, token: token + 1) == nil)
    }

    @Test func navigationKeepsOneReaderPerSelectedTopic() {
        let navigation = NavigationModel(dataSource: FakeDataSource(), topicPages: FakeTopicPages())
        let topic = topicSummary(1)
        let first = navigation.reader(for: topic)
        #expect(first != nil)
        #expect(navigation.reader(for: topic) === first)
        #expect(navigation.reader(for: topicSummary(2)) !== first)
    }
}
