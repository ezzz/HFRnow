import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRParsing
@testable import SwiftHFR
import Testing

/// Where the reply sheet comes from and where the reader goes after it: the page's own answer link (`#repondre_form`),
/// the topic's last page after a confirmed reply, and the texts shown on failure.
@MainActor
struct ReplyEntryTests {
    @Test func theReplyIsOfferedOnlyWhenThePageHasAnAnswerForm() async {
        let pages = FakeTopicPages { target in answerPage(target.page) }
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic)), title: "Sujet", source: pages)
        #expect(reader.replyTarget == nil)
        await reader.onAppear()
        #expect(reader.replyTarget == ReplyTarget(formURL: replyFormURL, topic: readerTopic))
        pages.handler = { target in answerPage(target.page, answerURL: nil) }
        await reader.refresh()
        #expect(reader.replyTarget == nil)
    }

    @Test func anAnswerLinkOnAnotherPortOffersNoReply() async {
        let other = url("https://forum.hardware.fr:8443/message.php?config=hfr.inc&cat=13&post=28563")
        let pages = FakeTopicPages { target in answerPage(target.page, answerURL: other) }
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic)), title: "", source: pages)
        await reader.onAppear()
        #expect(reader.replyTarget == nil)
    }

    @Test func anAnswerLinkThatNamesAnotherTopicOffersNoReply() async {
        // `readerTopic` is 13/28563: another post, another category, no topic at all.
        let links = [
            "https://forum.hardware.fr/message.php?config=hfr.inc&cat=13&post=6510&page=5&p=1",
            "https://forum.hardware.fr/message.php?config=hfr.inc&cat=5&post=28563&page=5&p=1",
            "https://forum.hardware.fr/message.php?config=hfr.inc&page=5&p=1"
        ]
        for link in links {
            let pages = FakeTopicPages { target in answerPage(target.page, answerURL: url(link)) }
            let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic)), title: "", source: pages)
            await reader.onAppear()
            #expect(reader.page?.topicID == readerTopic)
            #expect(reader.replyTarget == nil)
        }
    }

    @Test func retryingAFailedLatestPostLoadStillOpensAtTheLastMessage() async {
        let pages = FakeTopicPages { target in answerPage(min(target.page, 5)) }
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic), page: 2), title: "", source: pages)
        await reader.onAppear()
        pages.handler = { (_) async throws(ListLoadError) -> ReaderPage in throw .offline }
        await reader.composerDidClose(.sent(replyConfirmed))
        #expect(reader.error == .offline)
        pages.handler = { target in answerPage(min(target.page, 5)) }
        await reader.retry()
        #expect(pages.requests.map(\.page) == [2, 6, 6])
        #expect(reader.document?.anchor == 501)
    }

    @Test func aPageThatNamesNoTopicOffersNoReply() async {
        let pages = FakeTopicPages { target in
            var served = answerPage(target.page)
            served.topicID = nil
            return served
        }
        let reader = TopicReaderModel(target: ReaderTarget(source: .path("/hfr/a/b-sujet_1_1.htm")), title: "", source: pages)
        await reader.onAppear()
        #expect(reader.replyTarget == nil)
    }

    @Test func afterAReplyTheReaderOpensTheLastPageAtItsLastMessage() async {
        let pages = FakeTopicPages { target in answerPage(min(target.page, 5)) }
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic), page: 2, anchor: 200), title: "", source: pages)
        await reader.onAppear()
        await reader.composerDidClose(.sent(replyConfirmed))
        // Page 6 is asked for (the reply may have opened it); HFR serves the last page (`R24`), here 5.
        #expect(pages.requests.map(\.page) == [2, 6])
        #expect(reader.page?.currentPage == 5)
        #expect(reader.document?.anchor == 501)
        #expect(reader.document?.keepsScrollPosition == false)
        #expect(reader.replyConfirmation == "Votre réponse a été postée avec succès !")
        reader.clearReplyConfirmation()
        #expect(reader.replyConfirmation == nil)
    }

    @Test func anUnconfirmedReplyShowsTheLatestPostWithoutConfirmationAndClosingDoesNothing() async {
        let pages = FakeTopicPages { target in answerPage(min(target.page, 5)) }
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic), page: 2), title: "", source: pages)
        await reader.onAppear()
        await reader.composerDidClose(.keptDraft)
        await reader.composerDidClose(.discardedDraft)
        #expect(pages.requests.map(\.page) == [2])
        await reader.composerDidClose(.checkTopic)
        #expect(pages.requests.map(\.page) == [2, 6])
        #expect(reader.replyConfirmation == nil)
    }

    @Test func theLastMessageIsNeverTheContinuationBlock() async {
        let pages = FakeTopicPages { target in
            var served = answerPage(5)
            served.messages = [served.messages[0]]
            served.messages[0].isContinuation = true
            return target.page == 1 ? answerPage(1) : served
        }
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic)), title: "", source: pages)
        await reader.onAppear()
        await reader.showLatestPost()
        #expect(reader.document?.anchor == nil)
    }

    @Test func aCanonicalPathTopicMovesPastItsLastPageToo() async {
        let path = "/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_3.htm"
        let pages = FakeTopicPages { target in
            var served = answerPage(target.page)
            served.topicID = nil
            return served
        }
        let reader = TopicReaderModel(target: ReaderTarget(source: .path(path), page: 3), title: "", source: pages)
        await reader.onAppear()
        await reader.showLatestPost()
        #expect(pages.requests.last?.source == .path("/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_6.htm"))
    }

    // MARK: Captured pages

    @Test func aLoggedInTopicPageGivesItsAnswerLink() throws {
        let body = try LiveTopicPageSourceTests.capture("R61d-public-topic-last-page-own-post.html")
        let html = try #require(String(data: body, encoding: .utf8))
        let page = try LiveTopicPageSource.parse(
            html, pageURL: url("https://forum.hardware.fr/hfr/Discussions/Sports/muscu-topic-gringalets-sujet_6510_30.htm"),
            normalizer: LiveTopicPageSourceTests.MarkingNormalizer()
        )
        let expected = "https://forum.hardware.fr/message.php?config=hfr.inc&cat=13&post=6510&page=30&p=1&subcat=430"
            + "&sondage=0&owntopic=0&new=0"
        #expect(page.answerURL?.absoluteString == expected)
        #expect(page.topicID == TopicID(category: .forum(13), topic: 6510))
        // The reader's guard against a link to another topic holds on the real page.
        #expect(HFRURL.topicID(in: expected) == page.topicID)
    }

    @Test(arguments: ["R20-topic-p1-anon.html", "R31-topic-locked-anon.html"])
    func aPageWithoutAnswerFormGivesNoLink(_ file: String) throws {
        let body = try LiveTopicPageSourceTests.capture(file)
        let html = try #require(String(data: body, encoding: .utf8))
        let page = try LiveTopicPageSource.parse(
            html, pageURL: url("https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm"),
            normalizer: LiveTopicPageSourceTests.MarkingNormalizer()
        )
        #expect(page.answerURL == nil)
    }

    // MARK: Live poster and texts

    @Test func theLivePosterRefusesALinkOffTheForumWithoutARequest() async {
        let poster = LiveReplyPoster(session: HFRSession())
        await #expect(throws: PostingError.invalidFormURL) {
            try await poster.reply("texte", formURL: url("http://forum.hardware.fr/message.php?config=hfr.inc"))
        }
    }

    @Test func hfrsOwnSentenceIsShownOnARefusal() {
        // `W33` (public reply with an empty body) and the flood sentence (HFR-PROTOCOL §7 E15).
        let empty = "Vous devez remplir tous les champs avant de poster ce message"
        #expect(ComposerMessages.message(for: .rejected(message: empty)) == empty)
        #expect(ComposerMessages.message(for: .formUnavailable(message: "Sujet verrouillé")) == "Sujet verrouillé")
        let unknown = ComposerMessages.message(for: .unconfirmed(.unrecognizedAnswer(message: "Texte inattendu")))
        #expect(unknown.contains("peut-être été postée"))
        #expect(unknown.contains("« Texte inattendu »"))
    }

    @Test func onlyUnconfirmedSaysTheReplyMayHaveBeenPosted() {
        let notPosted: [PostingError] = [
            .rejected(message: nil), .notLoggedIn, .formUnavailable(message: nil), .network(.offline), .network(.cancelled),
            .invalidFormURL, .missingAction, .unsupportedForm(reason: "x"), .emptyInput(.text)
        ]
        for error in notPosted {
            #expect(!ComposerMessages.message(for: error).contains("peut-être"))
        }
        #expect(ComposerMessages.message(for: .unconfirmed(.transport(.timedOut))).contains("peut-être"))
    }
}

/// Page `number` of 5 of `readerTopic` with the answer link of a logged-in page.
private func answerPage(_ number: Int, maxPage: Int = 5, answerURL: URL? = replyFormURL) -> ReaderPage {
    var page = readerPage(page: number, maxPage: maxPage)
    page.answerURL = answerURL
    return page
}
