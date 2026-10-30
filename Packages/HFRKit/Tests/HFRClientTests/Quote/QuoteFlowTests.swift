import Foundation
import HFRModels
@testable import HFRNetwork
import Testing
@testable import HFRClient

/// What the quote flow refuses, and what happens to the multi-quote selection after each outcome of the reply.
/// Pages are captures; cookie values are fake.
@Suite("Quote flow: refusals and the multi-quote selection")
struct QuoteFlowTests {
    private static let conversation = TopicID(category: .privateMessages, topic: 3207033)
    private static let pizza = TopicID(category: .forum(13), topic: 28563)
    private static let posted = [1980875029, 1980875030]

    private static func token(_ topic: TopicID, _ number: Int = 1) -> QuoteSelectionToken {
        QuoteSelectionToken(forum: "hardwarefr", topic: topic, numreponse: number)
    }

    /// A session serving `pages` whose conversation `R47c` belongs to has `posted` selected.
    private static func conversationSession(_ pages: [Result<HTTPResponse, NetworkError>]) async -> ScriptedQuoteSession {
        let session = ScriptedQuoteSession(pages)
        await session.select(posted, in: conversation)
        return session
    }

    private static func failure(_ body: () async throws(QuoteError) -> QuoteComposer) async -> QuoteError? {
        do {
            _ = try await body()
            return nil
        } catch {
            return error
        }
    }

    // MARK: - Loading

    @Test("A message without quote link sends nothing")
    func noQuoteLink() async {
        let session = ScriptedQuoteSession([])
        let error = await Self.failure { () async throws(QuoteError) in
            try await QuoteFlow().quote(MessageActions(), through: session)
        }
        #expect(error == .noQuoteLink)
        #expect(await session.requests.isEmpty)
    }

    @Test("A multi-quote without any selected message sends nothing")
    func emptySelection() async throws {
        let session = ScriptedQuoteSession([])
        let url = try PostingCapture.pageURL("R47c")
        let error = await Self.failure { () async throws(QuoteError) in
            try await QuoteFlow().multiQuote(Self.token(Self.conversation), answerFormURL: url, through: session)
        }
        #expect(error == .emptySelection)
        #expect(await session.requests.isEmpty)
    }

    @Test(
        "A page that is not a reply composer with a prefill is no quote",
        arguments: ["R40a", "R47b", "R43a", "R45a", "R45b"]
    )
    func noQuote(page: String) async throws {
        let session = ScriptedQuoteSession([try PostingCapture.form(page)])
        let link = try PostingCapture.pageURL("R41a")
        let error = await Self.failure { () async throws(QuoteError) in
            try await QuoteFlow().quote(MessageActions(quoteURL: link), through: session)
        }
        #expect(error == .noQuote)
    }

    @Test("A multi-quote composer served without prefill (the selection was not used) is no quote")
    func multiQuoteWithoutPrefill() async throws {
        let session = await Self.conversationSession([try PostingCapture.form("R47b")])
        let link = try PostingCapture.pageURL("R47c")
        let error = await Self.failure { () async throws(QuoteError) in
            try await QuoteFlow().multiQuote(Self.token(Self.conversation), answerFormURL: link, through: session)
        }
        #expect(error == .noQuote)
        #expect(await session.selection(of: Self.conversation) == "|1980875029|1980875030")
    }

    @Test(
        "A multi-quote composer of another topic is refused",
        arguments: [
            TopicID(category: .privateMessages, topic: 3207034), TopicID(category: .forum(13), topic: 3207033),
            TopicID(category: .forum(13), topic: 28563)
        ]
    )
    func otherTopic(topic: TopicID) async throws {
        let session = ScriptedQuoteSession([try PostingCapture.form("R47c")])
        await session.select([1], in: topic)
        let link = try PostingCapture.pageURL("R47c")
        let error = await Self.failure { () async throws(QuoteError) in
            try await QuoteFlow().multiQuote(Self.token(topic), answerFormURL: link, through: session)
        }
        #expect(error == .otherTopic)
        #expect(await session.selection(of: topic) == "|1")
    }

    @Test("LOT-048's refusals come through: an anonymous composer, an off-forum link")
    func formErrors() async throws {
        let anonymous = ScriptedQuoteSession([try PostingCapture.form("R40b")])
        let anonymousLink = try PostingCapture.pageURL("R40b")
        let loggedOut = await Self.failure { () async throws(QuoteError) in
            try await QuoteFlow().quote(MessageActions(quoteURL: anonymousLink), through: anonymous)
        }
        #expect(loggedOut == .form(.notLoggedIn))
        let offForum = ScriptedQuoteSession([])
        let link = try #require(URL(string: "https://forum.hardware.fr:8443/message.php?config=hfr.inc&cat=13&post=1&numrep=2"))
        let refused = await Self.failure { () async throws(QuoteError) in
            try await QuoteFlow().quote(MessageActions(quoteURL: link), through: offForum)
        }
        #expect(refused == .form(.invalidFormURL))
        #expect(await offForum.requests.isEmpty)
    }

    // MARK: - The selection after the reply

    @Test("Messages selected after the composer was loaded stay selected; the posted ones go")
    func laterSelectionStays() async throws {
        let session = await Self.conversationSession([try PostingCapture.form("R47c"), try PostingCapture.answer("W14")])
        let flow = QuoteFlow()
        let composer = try await flow.multiQuote(
            Self.token(Self.conversation), answerFormURL: try PostingCapture.pageURL("R47c"), through: session
        )
        await session.select([1980875031], in: Self.conversation)
        await session.select([Self.posted[0]], in: Self.conversation) // unselected meanwhile: must not come back
        _ = try await flow.reply(composer.prefill, with: composer)
        #expect(await session.selection(of: Self.conversation) == "|1980875031")
    }

    @Test(
        "Without HFR's confirmation the selection is kept",
        arguments: ["W17b", "W20a", "W14x", "W17c", "transport", "http500", "W15"]
    )
    func failedReplyKeepsSelection(answer: String) async throws {
        let session = await Self.conversationSession([try PostingCapture.form("R47c"), try Self.answer(answer)])
        let flow = QuoteFlow()
        let composer = try await flow.multiQuote(
            Self.token(Self.conversation), answerFormURL: try PostingCapture.pageURL("R47c"), through: session
        )
        await #expect(throws: PostingError.self) { try await flow.reply(composer.prefill, with: composer) }
        #expect(await session.requests.count == 2)
        #expect(await session.selection(of: Self.conversation) == "|1980875029|1980875030")
    }

    @Test("A text refused before sending keeps the selection")
    func refusedTextKeepsSelection() async throws {
        let session = await Self.conversationSession([try PostingCapture.form("R47c")])
        let flow = QuoteFlow()
        let composer = try await flow.multiQuote(
            Self.token(Self.conversation), answerFormURL: try PostingCapture.pageURL("R47c"), through: session
        )
        await #expect(throws: PostingError.emptyInput(.text)) { try await flow.reply(" \n", with: composer) }
        #expect(await session.requests.count == 1)
        #expect(await session.selection(of: Self.conversation) == "|1980875029|1980875030")
    }

    @Test("A single quote leaves the selection alone, even after HFR confirmed the reply")
    func singleQuoteLeavesSelection() async throws {
        let session = await Self.conversationSession([try PostingCapture.form("R47a"), try PostingCapture.answer("W14")])
        let flow = QuoteFlow()
        // The quoted message is itself selected: the single quote still leaves the selection alone.
        let message = MessageActions(
            quoteURL: try PostingCapture.pageURL("R47a"), quoteSelection: Self.token(Self.conversation, Self.posted[1])
        )
        let composer = try await flow.quote(message, through: session)
        _ = try await flow.reply(composer.prefill, with: composer)
        #expect(await session.carried.first == ["quoteshardwarefr-prive-3207033=|1980875029|1980875030"])
        #expect(await session.selection(of: Self.conversation) == "|1980875029|1980875030")
    }

    @Test("On an account session, the topic's cookie goes to the answer link and only the posted messages are unselected")
    func accountSession() async throws {
        let session = HFRSession()
        for number in Self.posted + [1980875031] { await session.toggleQuote(Self.token(Self.conversation, number)) }
        await session.toggleQuote(Self.token(Self.pizza, 2666649))
        let answerLink = try PostingCapture.pageURL("R47c")
        #expect(await session.cookieNames(for: answerLink).contains("quoteshardwarefr-prive-3207033"))
        await session.unselect(Self.posted, of: Self.token(Self.conversation))
        #expect(await session.multiQuote(for: Self.token(Self.conversation)).value == "|1980875031")
        await session.unselect([1980875031], of: Self.token(Self.conversation))
        #expect(await !session.cookieNames(for: answerLink).contains("quoteshardwarefr-prive-3207033"))
        #expect(await session.multiQuote(for: Self.token(Self.pizza)).value == "|2666649")
    }

    /// A captured answer, a transport failure after sending, or an HTTP 500.
    private static func answer(_ id: String) throws -> Result<HTTPResponse, NetworkError> {
        let postURL = PostingCapture.url("https://forum.hardware.fr/bddpost.php?config=hfr.inc")
        switch id {
        case "transport": return .failure(.timedOut)
        case "http500": return .failure(.httpStatus(code: 500, url: postURL))
        default: return try PostingCapture.answer(id)
        }
    }
}
