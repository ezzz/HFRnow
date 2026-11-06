import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// The legacy quick actions of a row's menu (LOT-125, `Common.swift:2875-3093` @ 2440d79): which page each opens, and where.
struct TopicQuickActionsTests {
    private let topic = TopicID(category: .forum(13), topic: 28563)
    private let canonical = "/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_"
    /// `R25`'s shape: the last post as a message link, HFR picks its page.
    private let lastPostLink = "/forum2.php?config=hfr.inc&cat=13&post=28563&page=1&numreponse=39971312#t39971312"

    private func row(pages: Int = 12, current: Int? = nil, lastPost: Bool = true) -> TopicSummary {
        TopicSummary(
            topicID: topic, title: "Pizza", path: canonical + "1.htm", pageCount: pages, lastPagePath: canonical + "\(pages).htm",
            lastPost: lastPost ? LastPost(author: "a", path: lastPostLink) : nil, currentPage: current
        )
    }

    @Test func premierePageOpensPageOneAtItsTop() {
        #expect(TopicQuickActions.firstPage(of: row()) == TopicOpening(target: ReaderTarget(source: .topic(topic), page: 1)))
    }

    @Test func dernierePageOpensTheLastPageLinkAtItsTop() {
        let opening = TopicQuickActions.lastPage(of: row())
        #expect(opening == TopicOpening(target: ReaderTarget(source: .topic(topic), page: 12)))
    }

    @Test func dernierePageDropsTheAnchorOfItsLink() {
        var summary = row()
        summary.lastPagePath = canonical + "12.htm#t99"
        #expect(TopicQuickActions.lastPage(of: summary)?.target.anchor == nil)
    }

    @Test func derniereReponseOpensTheLastPostLinkAtTheLastMessage() throws {
        let opening = try #require(TopicQuickActions.lastReply(of: row(), in: .favorites))
        #expect(opening.atLastMessage)
        #expect(opening.target.numreponse == 39971312)
        let forum = try #require(TopicQuickActions.lastReply(of: row(), in: .forum(.forum(13), title: "Discussions")))
        #expect(forum == opening)
    }

    /// Legacy context `.favorites` (the "Drapeaux & Favoris" list): the last page first (`lastReplyURL`).
    @Test func derniereReponseOfTheFlagsListOpensTheLastPageAtTheLastMessage() {
        let opening = TopicQuickActions.lastReply(of: row(), in: .flagged)
        #expect(opening == TopicOpening(target: ReaderTarget(source: .topic(topic), page: 12), atLastMessage: true))
    }

    @Test func derniereReponseWithoutLastPostFallsBackToTheLastPage() {
        let opening = TopicQuickActions.lastReply(of: row(lastPost: false), in: .favorites)
        #expect(opening == TopicOpening(target: ReaderTarget(source: .topic(topic), page: 12), atLastMessage: true))
    }

    @Test func pageNumeroAcceptsOnlyTheTopicsPages() {
        #expect(TopicQuickActions.page(5, of: row()) == TopicOpening(target: ReaderTarget(source: .topic(topic), page: 5)))
        #expect(TopicQuickActions.page(0, of: row()) == nil)
        #expect(TopicQuickActions.page(13, of: row()) == nil)
        #expect(TopicQuickActions.pages(of: row()) == 1...12)
    }

    @Test func pageNumeroProposesTheReadPage() {
        #expect(TopicQuickActions.suggestedPage(of: row(current: 7)) == 7)
        #expect(TopicQuickActions.suggestedPage(of: row()) == 1)
        #expect(TopicQuickActions.suggestedPage(of: row(pages: 3, current: 9)) == 3)
    }

    @Test func aRowWithoutTopicNumberStillOpensItsPagesFromItsLink() {
        var summary = row()
        summary.topicID = nil
        #expect(TopicQuickActions.page(3, of: summary)?.target == ReaderTarget(source: .topic(topic), page: 3))
    }

    @Test func copierLeLienGivesTheFirstPageAsAnAbsoluteForumLink() {
        var favourite = row()
        favourite.path = lastPostLink
        favourite.firstPagePath = canonical + "1.htm"
        #expect(TopicQuickActions.link(of: favourite)?.absoluteString == "https://forum.hardware.fr" + canonical + "1.htm")
        #expect(TopicQuickActions.link(of: row())?.absoluteString == "https://forum.hardware.fr" + canonical + "1.htm")
    }

    @Test func copierLeLienNeverOffersAnotherHost() {
        let summary = TopicSummary(title: "x", path: "https://example.com/a", lastPagePath: "javascript:alert(1)")
        #expect(TopicQuickActions.link(of: summary) == nil)
    }
}
