import Foundation
import HFRModels
import HFRNetwork
import Testing
@testable import HFRClient

/// Differential tests on the captured quote composers: the prefill the flow returns is the `content_form` legacy read
/// on the same page (LOT-004 oracles), and the multi-quote composer posted as served is the captured `W14`.
@Suite("Quote flow: captured composers")
struct QuoteCaptureTests {
    private static let pizza = TopicID(category: .forum(13), topic: 28563)
    private static let conversation = TopicID(category: .privateMessages, topic: 3207033)

    private static func expectOraclePrefill(_ prefill: String, _ id: String) throws {
        let oracle = try QuoteCapture.prefill(id)
        #expect(prefill == oracle.decoded)
        // Served with CRLF inside the quoted text and bare LF after `[/quotemsg]`: the same text once line breaks are `\n`.
        #expect(prefill == oracle.served.replacing("\r\n", with: "\n"))
        #expect(prefill.hasPrefix("[quotemsg="))
    }

    @Test("A message's quote link gives HFR's prefill, as legacy read it", arguments: ["R41a", "R41b", "R47a"])
    func singleQuote(id: String) async throws {
        let url = try PostingCapture.pageURL(id)
        let session = ScriptedQuoteSession([try PostingCapture.form(id)])
        let composer = try await QuoteFlow().quote(MessageActions(quoteURL: url), through: session)
        try Self.expectOraclePrefill(composer.prefill, id)
        let requests = await session.requests
        #expect(requests.map(\.url) == [url])
        #expect(requests.first?.method == .get)
        #expect(composer.form.shape == .reply)
        #expect(composer.selection == nil)
    }

    /// A captured multi-quote composer, the selection that produced it, and the cookie its request carried.
    struct MultiQuoteCase: Sendable, CustomTestStringConvertible {
        let id: String
        let topic: TopicID
        let selected: [Int]
        let cookie: String
        var testDescription: String { id }
    }

    static let multiQuoteCases = [
        MultiQuoteCase(id: "R42", topic: pizza, selected: [2666649, 2666682], cookie: "quoteshardwarefr-13-28563=|2666649|2666682"),
        MultiQuoteCase(
            id: "R47c", topic: conversation, selected: [1980875029, 1980875030],
            cookie: "quoteshardwarefr-prive-3207033=|1980875029|1980875030"
        )
    ]

    @Test("The topic's answer link, sent with the topic's selection, gives one block per selected message", arguments: multiQuoteCases)
    func multiQuote(_ example: MultiQuoteCase) async throws {
        let (id, topic, selected) = (example.id, example.topic, example.selected)
        let url = try PostingCapture.pageURL(id)
        let session = ScriptedQuoteSession([try PostingCapture.form(id)])
        await session.select(selected, in: topic)
        let token = QuoteSelectionToken(forum: "hardwarefr", topic: topic, numreponse: selected[0])
        let composer = try await QuoteFlow().multiQuote(token, answerFormURL: url, through: session)
        try Self.expectOraclePrefill(composer.prefill, id)
        #expect(await session.requests.map(\.url) == [url])
        // The request carried exactly the selected messages, and loading the composer changed nothing.
        #expect(await session.carried == [[example.cookie]])
        #expect(composer.selection?.numbers == selected)
        #expect(await session.selection(of: topic) == "|" + selected.map(String.init).joined(separator: "|"))
    }

    @Test("W14: the R47c composer posted as served is the captured body; then only the posted messages are unselected")
    func multiQuoteReply() async throws {
        let other = TopicID(category: .forum(13), topic: 28563)
        let session = ScriptedQuoteSession([try PostingCapture.form("R47c"), try PostingCapture.answer("W14")])
        await session.select([1980875029, 1980875030], in: Self.conversation)
        await session.select([2666649], in: other)
        let token = QuoteSelectionToken(forum: "hardwarefr", topic: Self.conversation, numreponse: 1980875030)
        let flow = QuoteFlow()
        let composer = try await flow.multiQuote(token, answerFormURL: try PostingCapture.pageURL("R47c"), through: session)
        let result = try await flow.reply(composer.prefill, with: composer)
        #expect(result.message == "Votre réponse a été postée avec succès !")
        let post = try #require(await session.requests.last)
        let body = post.body.flatMap { String(bytes: $0, encoding: .utf8) }
        let boxes: Set<String> = ["signature", "smiley", "emaill", "delete"]
        #expect(body == (try PostingHarness.browserBody(of: "W14", checkboxes: boxes)))
        #expect(post.redirectPolicy == .doNotFollow)
        #expect(await session.selection(of: Self.conversation).isEmpty)
        #expect(await session.selection(of: other) == "|2666649")
    }
}
