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

    @Test func theDocumentScrollsToTheAnchorOnlyWhenThePostIsOnThePage() async throws {
        let pages = FakeTopicPages()
        let reader = model(pages, page: 2, anchor: 201)
        await reader.onAppear()
        #expect(reader.document?.anchor == 201)
        reader.follow(ReaderTarget(source: .topic(readerTopic), page: 4, anchor: 999))
        let linked = try #require(reader.linkedReader)
        await linked.onAppear()
        #expect(linked.document?.anchor == nil)
    }

    @Test func aTargetWithAnAnchorDrawsTheSeparatorAfterIt() async {
        let withAnchor = model(FakeTopicPages(), page: 2, anchor: 200)
        await withAnchor.onAppear()
        #expect(withAnchor.document?.html.contains("separator1") == true)
        let without = model(FakeTopicPages(), page: 2)
        await without.onAppear()
        #expect(without.document?.html.contains("separator1") == false)
    }

    @Test func aPostLinkOnThePageShownScrollsWithoutRefetching() async throws {
        let pages = FakeTopicPages()
        let reader = model(pages, page: 2)
        await reader.onAppear()
        reader.follow(ReaderTarget(source: .topic(readerTopic), page: 2, anchor: 201))
        #expect(pages.requests.count == 1)
        #expect(reader.linkedReader == nil)
        #expect(reader.scrollRequest?.anchor == 201)
        #expect(reader.scrollRequest?.token == reader.document?.token)
        reader.follow(ReaderTarget(source: .topic(readerTopic), page: 3, anchor: 301))
        let linked = try #require(reader.linkedReader)
        await linked.onAppear()
        #expect(pages.requests.last == ReaderTarget(source: .topic(readerTopic), page: 3, anchor: 301))
        #expect(linked.document?.anchor == 301)
    }

    /// LOT-137: a followed link opens another reader above this one; going back finds this page untouched, at the same
    /// document (so the web view keeps its scroll position), with nothing fetched again.
    @Test func aFollowedLinkKeepsThePageItLeftForTheWayBack() async throws {
        let pages = FakeTopicPages()
        let reader = model(pages, page: 2, anchor: 201)
        await reader.onAppear()
        let left = (page: reader.page, document: reader.document, shown: reader.shown)
        let other = TopicID(category: .forum(5), topic: 77)
        reader.follow(ReaderTarget(source: .topic(other), page: 9, anchor: 901))
        let linked = try #require(reader.linkedReader)
        // A second tap before the push lands keeps the first reader.
        reader.follow(ReaderTarget(source: .topic(other), page: 3))
        #expect(reader.linkedReader === linked)
        #expect(linked.requested == ReaderTarget(source: .topic(other), page: 9, anchor: 901))
        #expect(linked.title.isEmpty)
        await linked.onAppear()
        #expect(pages.requests.count == 2)
        reader.closeLinkedReader()
        #expect(reader.linkedReader == nil)
        #expect(reader.page == left.page)
        #expect(reader.document == left.document)
        #expect(reader.shown == left.shown)
        await reader.onAppear()
        #expect(pages.requests.count == 2)
    }

    @Test func aMessageLinkOpensThePageHFRServesAtTheMessage() async throws {
        // HFR answers a message link with the page that holds it (R25: page 1100); the fake serves page 4 here.
        let pages = FakeTopicPages { target in readerPage(page: target.numreponse == nil ? target.page : 4) }
        let reader = model(pages)
        await reader.onAppear()
        let link = ReaderTarget(source: .topic(readerTopic), anchor: 401, numreponse: 401)
        reader.follow(link)
        let linked = try #require(reader.linkedReader)
        #expect(linked.title == "Sujet")
        await linked.onAppear()
        #expect(pages.requests.last == link)
        #expect(linked.page?.currentPage == 4)
        #expect(linked.document?.anchor == 401)
        #expect(linked.canGoToPrevious)
        // The same message again, now on screen: it scrolls without asking HFR again.
        linked.follow(link)
        #expect(pages.requests.count == 2)
        #expect(linked.linkedReader == nil)
        #expect(linked.scrollRequest?.anchor == 401)
        // A refresh reloads page 4 itself, not the message link.
        await linked.refresh()
        #expect(pages.requests.last == ReaderTarget(source: .topic(readerTopic), page: 4))
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
}

/// Where the reader sends a link (LOT-137): kept apart so each type body stays under SwiftLint's limit.
extension TopicReaderModelTests {
    @Test func linksOpenInTheReaderOrOutside() async {
        let pages = FakeTopicPages()
        let reader = model(pages)
        await reader.onAppear()
        let post = url("https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_4.htm#t401")
        let opened = ReaderTarget(source: .topic(readerTopic), page: 4, anchor: 401)
        #expect(reader.action(forLink: post, defaultBrowser: false) == .reader(opened))
        #expect(reader.action(forLink: post, defaultBrowser: true) == .reader(opened))
        let web = url("https://example.com/a")
        #expect(reader.action(forLink: web, defaultBrowser: false) == .inAppBrowser(web))
        let logout = url("https://forum.hardware.fr/user/logout.php")
        #expect(reader.action(forLink: logout, defaultBrowser: false) == .inAppBrowser(logout))
        #expect(reader.action(forLink: url("mailto:someone@example.com"), defaultBrowser: false) == .ignored)
        #expect(reader.action(forLink: url("mailto:someone@example.com"), defaultBrowser: true) == .ignored)
    }

    /// A private conversation linked from a public topic is known as one, so the view gives it no composer (LOT-128).
    @Test func aPrivateConversationLinkIsKnownAsOne() throws {
        let reader = model(FakeTopicPages())
        #expect(!reader.isPrivateConversation)
        let link = url("https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=prive&post=4242&page=2")
        guard case .reader(let target) = reader.action(forLink: link, defaultBrowser: false) else {
            Issue.record("A private conversation link opens in the app")
            return
        }
        reader.follow(target)
        #expect(try #require(reader.linkedReader).isPrivateConversation)
    }

    /// "Navigateur par défaut" (LOT-119 stores it, LOT-137 applies it): web links go to the system browser; forum topic
    /// links stay in the app either way.
    @Test func theDefaultBrowserSettingSendsWebLinksToTheSystemBrowser() {
        let reader = model(FakeTopicPages())
        let web = url("https://example.com/a")
        #expect(reader.action(forLink: web, defaultBrowser: true) == .defaultBrowser(web))
        // A forum page the router does not open as a topic (a profile) is a web link too.
        let profile = url("https://forum.hardware.fr/hfr/profil-12345.htm")
        #expect(reader.action(forLink: profile, defaultBrowser: true) == .defaultBrowser(profile))
        #expect(reader.action(forLink: profile, defaultBrowser: false) == .inAppBrowser(profile))
    }

    /// LOT-095 follow-up: a link carrying `cat` and `post` that the router does not route as a topic page (an answer link, a
    /// single-message view) is opened outside, never in the reader with the session.
    @Test func aForumLinkTheRouterRefusesIsNotOpenedWithTheSession() {
        let reader = model(FakeTopicPages())
        let answer = url("https://forum.hardware.fr/message.php?config=hfr.inc&cat=13&post=28563&page=2#formulaire")
        #expect(reader.action(forLink: answer, defaultBrowser: false) == .inAppBrowser(answer))
        let quoteOnly = url("https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=28563&page=2&quote_only=1")
        #expect(reader.action(forLink: quoteOnly, defaultBrowser: false) == .inAppBrowser(quoteOnly))
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
