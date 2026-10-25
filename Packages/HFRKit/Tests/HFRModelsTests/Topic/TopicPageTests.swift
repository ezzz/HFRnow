import Foundation
import Testing
@testable import HFRModels

@Suite struct TopicPageTests {
    private let topic = TopicID(category: .forum(13), topic: 1711)

    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    private func makeMessage(id: Int) throws -> Message {
        Message(
            id: id,
            author: "Alice",
            avatarURL: try url("https://forum-images.hardware.fr/a.png"),
            dateText: "25-10-2026 10:00:00",
            content: MessageContent(
                html: "<p>hi</p>",
                signatureHTML: "<span class=\"signature\">sig</span>",
                images: [MessageImage(url: try url("https://reho.st/x.png"), linkURL: try url("https://example.org/"), altText: "x")],
                smileys: [MessageSmiley(code: ":)", url: try url("https://forum-images.hardware.fr/icones/smile.gif"), kind: .standard)],
                links: [MessageLink(url: try url("https://example.org/"), text: "ex", isInSignature: true)],
                embeds: [MessageEmbed(
                    provider: .youtube,
                    sourceURL: try url("https://youtu.be/abc?t=30"),
                    embedURL: try url("https://www.youtube.com/embed/abc?start=30"),
                    startSeconds: 30
                )]
            ),
            quotes: [MessageQuote(author: "Bob", depth: 2, citedNumreponse: 99)],
            editNote: "Alice le 25-10-2026",
            quotedByCount: 3,
            quotedByURL: try url("https://forum.hardware.fr/q"),
            actions: MessageActions(
                quoteURL: try url("https://forum.hardware.fr/message.php?cat=13&post=1711&numreponse=5"),
                quoteSelection: QuoteSelectionToken(forum: "hardwarefr", topic: topic, numreponse: id)
            )
        )
    }

    @Test func fullPageRoundTrips() throws {
        let page = TopicPage(
            topicID: topic,
            title: "Topic",
            currentPage: 2,
            maxPage: 5,
            answerFormURL: try url("https://forum.hardware.fr/message.php?cat=13&post=1711"),
            answerFormFields: ["cat": "13", "post": "1711"],
            isUnreadable: true,
            poll: Poll(question: "Q?", kind: .results([PollResult(id: 1, label: "A", percentage: 16.7, voteCount: 5)])),
            searchFormFields: ["word": ""],
            messages: [try makeMessage(id: 10), try makeMessage(id: 11)]
        )
        #expect(try roundTrip(page) == page)
    }

    @Test func messageIdentityIsTheNumber() throws {
        #expect(try makeMessage(id: 10).id == 10)
        #expect(try makeMessage(id: 10) != makeMessage(id: 11))
    }

    @Test func postIDCombinesTheTopicWithTheMessageNumber() throws {
        let page = TopicPage(topicID: topic, title: "t", messages: [try makeMessage(id: 10)])
        #expect(page.postID(of: page.messages[0]) == PostID(topic: topic, numreponse: 10))
    }

    @Test func sameNumreponseInAnotherCategoryIsAnotherPost() {
        let first = PostID(topic: TopicID(category: .forum(1), topic: 5), numreponse: 10)
        let second = PostID(topic: TopicID(category: .forum(2), topic: 5), numreponse: 10)
        #expect(first != second)
        #expect(Set([first, second]).count == 2)
    }

    @Test func postIDIsNilWhenTheTopicIsUnknown() throws {
        let page = TopicPage(title: "t", messages: [try makeMessage(id: 10)])
        #expect(page.postID(of: page.messages[0]) == nil)
    }

    @Test func initializerFloorsPageNumbers() {
        let page = TopicPage(title: "t", currentPage: 0, maxPage: -2)
        #expect(page.currentPage == 1)
        #expect(page.maxPage == 1)
    }

    @Test func noActionByDefault() {
        #expect(MessageActions() == MessageActions(quoteURL: nil))
        #expect(MessageActions() != MessageActions(editURL: URL(string: "https://forum.hardware.fr/e")))
    }

    @Test func quoteDepthIsFlooredAndAnonymousQuotesKeepNilAuthor() throws {
        let quote = MessageQuote(depth: 0)
        #expect(quote.depth == 1)
        #expect(try roundTrip(quote).author == nil)
    }

    @Test func messageContentDefaultsAreEmptyLists() throws {
        let content = MessageContent(html: "x")
        #expect(content.signatureHTML == nil)
        #expect(content.images.isEmpty && content.smileys.isEmpty && content.links.isEmpty && content.embeds.isEmpty)
        #expect(try roundTrip(content) == content)
    }

    @Test func signatureDifferenceMakesContentDifferent() {
        #expect(MessageContent(html: "x") != MessageContent(html: "x", signatureHTML: "s"))
    }

    @Test func smileyKindsEncodeAsWords() throws {
        let data = try JSONEncoder().encode([MessageSmiley.Kind.standard, .custom])
        #expect(try text(of: data) == #"["standard","custom"]"#)
    }

    @Test func diagnosticsNeverRevealFormFieldValues() throws {
        let poll = Poll(question: "Q?", kind: .votable(options: [], hiddenFields: ["hash_check": "POLL-SECRET"]))
        let page = TopicPage(
            title: "t",
            answerFormFields: ["hash_check": "ANSWER-SECRET"],
            poll: poll,
            searchFormFields: ["hash_check": "SEARCH-SECRET"]
        )
        var dumped = ""
        dump(page, to: &dumped)
        let subjects = [
            page.description, page.debugDescription, "\(page)", String(reflecting: page), dumped, "\(poll)", String(reflecting: poll)
        ]
        for subject in subjects {
            #expect(!subject.contains("SECRET"))
        }
        #expect(page.description.contains("2 form fields"))
        #expect(poll.kind.description.contains("1 hidden fields"))
    }
}
