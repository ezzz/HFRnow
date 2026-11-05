import Foundation
import HFRModels
@testable import HFRNetwork
import HFRParsing
import Testing
@testable import HFRClient

/// LOT-054: the vote form read from a topic page (`R83`, `R32b`) is sent as `W42` sent it and confirmed only by HFR's
/// vote sentence (`W42`); a second vote is `alreadyVoted` (`W43`, `W44`). Tokens are fake.
@Suite("Poll vote")
struct PollVoteFlowTests {
    /// The token the scripted session holds: the captures' bodies carry `REDACTED` in its place.
    static let token = "REDACTED"
    /// The topic of `R83` and `W42`-`W44` (anonymized id).
    static let ownTopic = TopicID(category: .forum(10), topic: 9_900_002)
    let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))

    /// What one vote did.
    struct Run {
        var result: Result<PollVoteResult, PollVoteError>
        var requests: [HTTPRequest]
    }

    // MARK: - Body

    @Test("The vote of answer 1 on R83 is the request W42 sent, byte for byte, once, to the form's action")
    func r83VoteIsW42Request() async throws {
        let run = try await Self.vote(1, onPage: "R83-public-own-topic-poll-form-logged-in", answer: "W42")
        let post = try #require(run.requests.first)
        #expect(run.requests.count == 1)
        #expect(post.method == .post)
        #expect(post.redirectPolicy == .doNotFollow)
        let meta = try Capture.meta("W42")
        #expect(post.url.absoluteString == meta.url)
        #expect(post.body.flatMap { String(bytes: $0, encoding: .utf8) } == meta.requestBody)
        #expect(PollVoteFlow.voteURL.absoluteString == meta.url)
    }

    @Test("Every captured vote body (W42-W44) is the one the flow builds from R83")
    func everyVoteBodyIsTheFlowsBody() throws {
        let form = try PollVoteForm(poll: Self.poll("R83-public-own-topic-poll-form-logged-in"), choice: 1)
        let body = form.body(token: Self.token).encodedString
        for id in ["W42", "W43", "W44"] {
            #expect(try Capture.meta(id).requestBody == body, "\(id)")
            #expect(try Capture.meta(id).requestFields == form.body(token: Self.token).fields.map(\.name), "\(id)")
        }
    }

    @Test("The body follows the form of another poll (R32b): its own values, the chosen answer, the Voter button")
    func r32bBody() throws {
        let form = try PollVoteForm(poll: Self.poll("R32b-topic-poll-logged-in-not-voted"), choice: 7)
        let body = form.body(token: "t0k").encodedString
        #expect(
            body == "hash_check=t0k&cat=13&p=1&page=1&sondage=1&owntopic=0&subcat=431&numeropost=98162"
                + "&hash_check=t0k&reponse=7&sondage_submit=Voter"
        )
        #expect(form.topic == TopicID(category: .forum(13), topic: 98_162))
    }

    // MARK: - Answers

    @Test("W42 is HFR's confirmation: the topic, the answer, HFR's sentence and the topic page it refreshes to")
    func w42Confirmed() async throws {
        let run = try await Self.vote(1, onPage: "R83-public-own-topic-poll-form-logged-in", answer: "W42")
        let result = try run.result.get()
        #expect(result.topic == Self.ownTopic)
        #expect(result.choice == 1)
        #expect(result.message == "Votre vote a bien été pris en compte !")
        #expect(result.refreshURL.absoluteString == "https://forum.hardware.fr/hfr/Programmation/iOS/sujet_9900002_1.htm")
    }

    @Test("A second vote, from the account (W43) or a linked one (W44), is alreadyVoted", arguments: ["W43", "W44"])
    func alreadyVoted(answer: String) async throws {
        let run = try await Self.vote(2, onPage: "R83-public-own-topic-poll-form-logged-in", answer: answer)
        #expect(run.result == .failure(.alreadyVoted))
        #expect(run.requests.count == 1)
    }

    @Test(
        "Other answers are refusals or unconfirmed, never a success: a write's 'avec succès' is not a vote's",
        arguments: [
            ("W17c-mp-reply-logged-out-rejected", PollVoteError.notLoggedIn),
            ("W17b-mp-reply-bad-token-rejected", .rejected(message: nil)),
            ("W20a-mp-reply-flood", .rejected(message: nil)),
            ("W30-public-reply-success", .unconfirmed(.unrecognizedAnswer(message: "Votre réponse a été postée avec succès !"))),
            ("R83-public-own-topic-poll-form-logged-in", .unconfirmed(.unrecognizedAnswer(message: nil)))
        ]
    )
    func otherAnswers(file: String, expected: PollVoteError) async throws {
        let session = ScriptedFlagSession([.success(try Capture.response(file, url: PollVoteFlow.voteURL))], hashCheck: Self.token)
        let form = try Self.form("R83-public-own-topic-poll-form-logged-in", choice: 1)
        let result = await Self.result { try await PollVoteFlow().vote(form, through: session) }
        switch (result, expected) {
        case (.failure(.rejected(let message)), .rejected(nil)):
            // The token and flood sentences are HFR's own; only the kind matters here.
            #expect(message?.isEmpty == false)
        default:
            #expect(result == .failure(expected), "\(file)")
        }
    }

    @Test("W42 answering a vote on another topic (R32b's) is not that vote's confirmation: its refresh names 9900002")
    func confirmationOfAnotherTopic() async throws {
        let session = ScriptedFlagSession([try Self.answer("W42")], hashCheck: Self.token)
        let form = try Self.form("R32b-topic-poll-logged-in-not-voted", choice: 1)
        let result = await Self.result { try await PollVoteFlow().vote(form, through: session) }
        #expect(result == .failure(.unconfirmed(.unrecognizedAnswer(message: "Votre vote a bien été pris en compte !"))))
    }

    @Test("The refresh is a page of the topic only by its sujet_<post>_<page>.htm name", arguments: [
        ("https://forum.hardware.fr/hfr/Programmation/iOS/sujet_9900002_1.htm", true),
        ("https://forum.hardware.fr/hfr/Programmation/iOS/sujet_9900002_12.htm", true),
        ("https://forum.hardware.fr/hfr/Programmation/iOS/sujet_99000021_1.htm", false),
        ("https://forum.hardware.fr/hfr/Programmation/iOS/sujet_9900002_.htm", false),
        ("https://forum.hardware.fr/hfr/Programmation/iOS/sujet_9900002_1.html", false),
        ("https://forum.hardware.fr/hfr/Programmation/iOS/liste_sujet-1.htm", false),
        // The same topic number in another category (Discussions = 13) is another topic.
        ("https://forum.hardware.fr/hfr/Discussions/iOS/sujet_9900002_1.htm", false),
        ("https://forum.hardware.fr/hfr/Inconnu/iOS/sujet_9900002_1.htm", false),
        // A topic at the category's root has no sub-forum directory (list links of R04, R27).
        ("https://forum.hardware.fr/hfr/Programmation/sujet_9900002_1.htm", true),
        ("https://forum.hardware.fr/hfr/Programmation/iOS/x/sujet_9900002_1.htm", false),
        ("https://forum.hardware.fr/forum/Programmation/iOS/sujet_9900002_1.htm", false)
    ])
    func refreshNamesTheTopic(raw: String, expected: Bool) throws {
        let url = try #require(URL(string: raw))
        #expect(PollVoteFlow.isPage(of: Self.ownTopic, url) == expected)
    }

    @Test("A redirect is not HFR's confirmation, even with the confirmation body")
    func redirectIsUnconfirmed() async throws {
        var moved = try Capture.response("W42-poll-vote-success", url: PollVoteFlow.voteURL)
        moved.statusCode = 302
        moved.headers["Location"] = "/login.php"
        let session = ScriptedFlagSession([.success(moved)], hashCheck: Self.token)
        let form = try Self.form("R83-public-own-topic-poll-form-logged-in", choice: 1)
        let result = await Self.result { try await PollVoteFlow().vote(form, through: session) }
        #expect(result == .failure(.unconfirmed(.unrecognizedAnswer(message: nil))))
    }

    @Test(
        "A failure after sending is unconfirmed; a request that could not be built is a plain failure",
        arguments: [
            (NetworkError.timedOut, PollVoteError.unconfirmed(.transport(.timedOut))),
            (.offline, .unconfirmed(.transport(.offline))),
            (.cancelled, .unconfirmed(.transport(.cancelled))),
            (.invalidRequest(reason: "x"), .network(.invalidRequest(reason: "x")))
        ]
    )
    func transportFailures(failure: NetworkError, expected: PollVoteError) async throws {
        let session = ScriptedFlagSession([.failure(failure)], hashCheck: Self.token)
        let form = try Self.form("R83-public-own-topic-poll-form-logged-in", choice: 1)
        let result = await Self.result { try await PollVoteFlow().vote(form, through: session) }
        #expect(result == .failure(expected))
        #expect(await session.requests.count == 1)
    }

    @Test("An HTTP error status is unconfirmed: the POST reached HFR")
    func httpStatusIsUnconfirmed() async throws {
        let failed = HTTPResponse(statusCode: 500, url: PollVoteFlow.voteURL)
        let session = ScriptedFlagSession([.success(failed)], hashCheck: Self.token)
        let form = try Self.form("R83-public-own-topic-poll-form-logged-in", choice: 1)
        let result = await Self.result { try await PollVoteFlow().vote(form, through: session) }
        #expect(result == .failure(.unconfirmed(.transport(.httpStatus(code: 500, url: PollVoteFlow.voteURL)))))
    }

    @Test("A session without token sends nothing", arguments: [nil, ""] as [String?])
    func missingToken(token: String?) async throws {
        let session = ScriptedFlagSession([try Self.answer("W42")], hashCheck: token)
        let form = try Self.form("R83-public-own-topic-poll-form-logged-in", choice: 1)
        let result = await Self.result { try await PollVoteFlow().vote(form, through: session) }
        #expect(result == .failure(.missingToken))
        #expect(await session.requests.isEmpty)
    }

    // MARK: - Form checks (nothing is sent)

    @Test("A results poll (closed R33a, already voted R33b) is not votable", arguments: [
        "R33a-topic-poll-closed-anon", "R33b-topic-poll-already-voted"
    ])
    func resultsAreNotVotable(page: String) async throws {
        let run = try await Self.vote(1, onPage: page, answer: "W42")
        #expect(run.result == .failure(.notVotable))
        #expect(run.requests.isEmpty)
    }

    @Test("A choice that is not an answer of the poll is refused", arguments: [0, -1, 3, 11])
    func invalidChoice(choice: Int) async throws {
        let run = try await Self.vote(choice, onPage: "R83-public-own-topic-poll-form-logged-in", answer: "W42")
        #expect(run.result == .failure(.invalidChoice))
        #expect(run.requests.isEmpty)
    }

    @Test("Every answer of R32b can be chosen")
    func everyAnswer() throws {
        let poll = try Self.poll("R32b-topic-poll-logged-in-not-voted")
        for choice in 1...10 {
            #expect(try PollVoteForm(poll: poll, choice: choice).choice == choice)
        }
    }

    @Test(
        "A form other than the captured one is refused: its body would be guessed",
        arguments: [
            "extra field", "missing field", "non-numeric value", "empty value", "zero topic", "zero category",
            "other answer field", "several choices", "no answer"
        ]
    )
    func unsupportedForm(change: String) async throws {
        let poll = try Self.poll("R83-public-own-topic-poll-form-logged-in")
        guard case .votable(var options, var fields) = poll.kind else { throw Capture.Missing(name: "votable R83") }
        var maxChoices = 1
        switch change {
        case "extra field": fields["verifrequet"] = "1100"
        case "missing field": fields["sondage"] = nil
        case "non-numeric value": fields["page"] = "1&reponse=2"
        case "empty value": fields["subcat"] = ""
        case "zero topic": fields["numeropost"] = "0"
        case "zero category": fields["cat"] = "0"
        case "other answer field": options[1].fieldName = "reponse2"
        case "several choices": maxChoices = 2
        default: options = []
        }
        let changed = Poll(question: poll.question, maxChoices: maxChoices, kind: .votable(options: options, hiddenFields: fields))
        let session = ScriptedFlagSession([try Self.answer("W42")], hashCheck: Self.token)
        let result = await Self.result {
            try await PollVoteFlow().vote(1, in: changed, through: session, after: { .valid })
        }
        #expect(result == .failure(.unsupportedPoll), "\(change)")
        #expect(await session.requests.isEmpty)
    }

    // MARK: - Helpers

    /// Counts the session checks a test's scripted check ran.
    actor Counter {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    /// The poll of the topic page `file`, as `PollParser` reads it.
    static func poll(_ file: String) throws -> Poll {
        guard let poll = try PollParser.poll(in: Capture.page(file)) else { throw Capture.Missing(name: "poll in \(file)") }
        return poll
    }

    static func form(_ file: String, choice: Int) throws -> PollVoteForm {
        try PollVoteForm(poll: poll(file), choice: choice)
    }

    /// The vote answer `id` (`W42`-`W44`) at the vote URL.
    static func answer(_ id: String) throws -> Result<HTTPResponse, NetworkError> {
        let files = ["W42": "W42-poll-vote-success", "W43": "W43-poll-vote-already-voted",
                     "W44": "W44-poll-vote-linked-account-already-voted"]
        guard let file = files[id] else { throw Capture.Missing(name: id) }
        return .success(try Capture.response(file, url: PollVoteFlow.voteURL))
    }

    /// Votes `choice` on the poll of `page` in a confirmed session holding the token, the POST answered `answer`.
    static func vote(_ choice: Int, onPage page: String, answer id: String) async throws -> Run {
        let session = ScriptedFlagSession([try answer(id)], hashCheck: token)
        let poll = try poll(page)
        let result = await result { try await PollVoteFlow().vote(choice, in: poll, through: session, after: { .valid }) }
        return Run(result: result, requests: await session.requests)
    }

    /// The outcome of `vote`; an error that is not a `PollVoteError` is recorded as an issue.
    static func result(_ vote: () async throws -> PollVoteResult) async -> Result<PollVoteResult, PollVoteError> {
        do {
            return .success(try await vote())
        } catch let error as PollVoteError {
            return .failure(error)
        } catch {
            Issue.record("unexpected error \(error)")
            return .failure(.unconfirmed(.unrecognizedAnswer(message: "unexpected")))
        }
    }

    func cookie(_ name: String, _ value: String) -> StoredCookie {
        StoredCookie(name: name, value: value, domain: ".hardware.fr", path: "/", expiresDate: now.addingTimeInterval(86_400))
    }
}
