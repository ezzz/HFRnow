import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// Poll vote (LOT-054, audit D11): sends the answer chosen on a topic page's voting form in the account's session and
/// reports it done only when HFR confirmed it with its vote sentence (`W42`).
///
/// The vote is sent once: the transport never retries, and a failure after sending is `unconfirmed`, never a success
/// nor a plain failure. It leaves only once LOT-044 confirmed the session just before it, as every flag write (#314).
/// Legacy posted the form's hidden fields from an unordered dictionary, without `sondage_submit`, and called any answer
/// without a `.hop` link a success (`PollData.swift:45-99` @ 2440d79); this flow sends the captured body and reads
/// HFR's own sentence.
public struct PollVoteFlow: Sendable {
    /// What the vote asks before it leaves: the health of the account session, from one GET of HFR (LOT-044).
    typealias SessionCheck = () async throws(NetworkError) -> SessionHealth

    /// The session check of the public entry point.
    private let refresh: SessionRefreshFlow

    /// Creates the flow.
    public init() {
        self.init(refresh: SessionRefreshFlow())
    }

    /// A flow whose session check is `refresh` (tests: a refresh flow with scripted probes).
    init(refresh: SessionRefreshFlow) {
        self.refresh = refresh
    }

    /// Votes for the answer `choice` (a `PollOption.id`) of `poll`, a voting form read from a topic page by
    /// `PollParser`, in `session`.
    ///
    /// The form is checked first, then the session (one GET of the profile page, which also records a fresh token),
    /// then one POST to `/user/vote.php?config=hfr.inc` carries the account's token.
    /// - Throws: `notVotable`, `unsupportedPoll`, `invalidChoice`, `sessionNotConfirmed`, `missingToken`, `alreadyVoted`,
    ///   `notLoggedIn`, `rejected`, `unconfirmed`, `network`.
    public func vote(_ choice: Int, in poll: Poll, session: HFRSession) async throws(PollVoteError) -> PollVoteResult {
        try await vote(choice, in: poll, through: session, after: check(session))
    }

    // MARK: - Steps

    /// `vote`, sent only when `check` says the account session is valid; a form that cannot be sent asks nothing.
    func vote(
        _ choice: Int, in poll: Poll, through session: any PostingSession, after check: SessionCheck
    ) async throws(PollVoteError) -> PollVoteResult {
        let form = try PollVoteForm(poll: poll, choice: choice)
        try await Self.confirm(check)
        return try await vote(form, through: session)
    }

    /// Sends `form` with the session's token, without any session check.
    func vote(_ form: PollVoteForm, through session: any PostingSession) async throws(PollVoteError) -> PollVoteResult {
        guard let token = await session.hashCheck, !token.isEmpty else { throw .missingToken }
        // A redirect is not followed: HFR answers the vote in place (`W42`-`W44`), anything else is not its confirmation.
        let request = HTTPRequest.post(Self.voteURL, form: form.body(token: token), redirectPolicy: .doNotFollow)
        let response = try await exchange(request, through: session)
        return try Self.confirmation(of: form, in: response)
    }

    // MARK: - Helpers

    /// The vote form's action (`R32a`, `R32b`, `R83`), the URL `W42` posted to.
    static let voteURL: URL = {
        guard let url = URL(string: "https://forum.hardware.fr/user/vote.php?config=hfr.inc") else {
            preconditionFailure("The vote URL literal is valid")
        }
        return url
    }()

    /// HFR's sentence to a second vote, from the same account (`W43`) or a linked one (`W44`).
    static let alreadyVotedSentence = "Désolé, vous avez déjà voté !"

    /// The entry point's check: LOT-044's refresh of `session`, which also merges the cookies and token HFR sends back.
    private func check(_ session: HFRSession) -> SessionCheck {
        let refresh = self.refresh
        return { () async throws(NetworkError) -> SessionHealth in try await refresh.refresh(session) }
    }

    /// Lets the vote leave only after a `valid` session check; a check that could not be done is a `network` failure.
    private static func confirm(_ check: SessionCheck) async throws(PollVoteError) {
        if Task.isCancelled { throw .network(.cancelled) }
        let health: SessionHealth
        do throws(NetworkError) {
            health = try await check()
        } catch {
            throw .network(error)
        }
        guard health == .valid else { throw .sessionNotConfirmed(health) }
    }

    /// Sends `request` once. Before it leaves the device a failure is `network`; after, HFR may have counted it.
    private func exchange(_ request: HTTPRequest, through session: any PostingSession) async throws(PollVoteError)
        -> HTTPResponse {
        if Task.isCancelled { throw .network(.cancelled) }
        do {
            return try await session.send(request)
        } catch .invalidRequest(let reason) {
            throw .network(.invalidRequest(reason: reason))
        } catch {
            throw .unconfirmed(.transport(error))
        }
    }

    /// Success needs LOT-037's vote confirmation (`Context.pollVote`): a link-less `.hop` with exactly HFR's vote
    /// sentence and a refresh to the forum (`W42`). The write confirmations ("avec succès") are not a vote's.
    static func confirmation(of form: PollVoteForm, in response: HTTPResponse) throws(PollVoteError) -> PollVoteResult {
        guard !response.isRedirect else { throw .unconfirmed(.unrecognizedAnswer(message: nil)) }
        let answer: HopResponse
        do {
            answer = try HopResponseParser.classify(
                html: response.decodedText().text, context: .pollVote, requestURL: voteURL
            )
        } catch {
            throw .unconfirmed(.unrecognizedAnswer(message: nil))
        }
        switch answer.kind {
        case .success:
            guard let message = answer.message, let refreshURL = answer.refreshURL else {
                throw .unconfirmed(.unrecognizedAnswer(message: answer.message))
            }
            // The sentence names no poll; the refresh to the topic page is HFR's only tie to this vote (`W42`).
            guard isPage(of: form.topic, refreshURL) else { throw .unconfirmed(.unrecognizedAnswer(message: message)) }
            return PollVoteResult(topic: form.topic, choice: form.choice, message: message, refreshURL: refreshURL)
        case .rejected:
            if answer.message == alreadyVotedSentence { throw .alreadyVoted }
            throw .rejected(message: answer.message)
        case .loggedOut:
            throw .notLoggedIn
        case .alreadyAlerted, .unrecognized:
            throw .unconfirmed(.unrecognizedAnswer(message: answer.message))
        }
    }
}

extension PollVoteFlow {
    /// `url` is a page of `topic` as `W42` refreshes to it: `/hfr/<cat>/<sub>/sujet_<post>_<page>.htm`, read only for
    /// its `sujet_<post>_` file name (the category is a slug, not the form's `cat`).
    static func isPage(of topic: TopicID, _ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard name.hasPrefix("sujet_\(topic.topic)_"), name.hasSuffix(".htm") else { return false }
        let page = name.dropFirst("sujet_\(topic.topic)_".count).dropLast(".htm".count)
        return FlagLink.positiveInteger(String(page)) != nil
    }
}

/// A voting form ready to send: the captured fields of the poll block and one chosen answer.
///
/// Only the captured form is accepted (`R32a`, `R32b`, `R83`): the hidden inputs `cat, p, page, sondage, owntopic,
/// subcat, numeropost, hash_check` with numeric values, and single-choice radios named `reponse` valued 1...N.
struct PollVoteForm: Sendable, Equatable {
    /// The hidden inputs other than the token, in the form's document order.
    static let fieldOrder = ["cat", "p", "page", "sondage", "owntopic", "subcat", "numeropost"]
    /// The radio name of every answer (`R32a`, `R32b`, `R83`).
    static let answerField = "reponse"

    /// Values of `fieldOrder`, in that order.
    let values: [String]
    /// The topic, from `cat` and `numeropost`.
    let topic: TopicID
    /// The chosen answer's position.
    let choice: Int

    /// Checks `poll` and `choice`; nothing is sent.
    /// - Throws: `notVotable`, `unsupportedPoll`, `invalidChoice`.
    init(poll: Poll, choice: Int) throws(PollVoteError) {
        guard case .votable(let options, let hiddenFields) = poll.kind else { throw .notVotable }
        guard
            poll.maxChoices == 1,
            !options.isEmpty,
            options.allSatisfy({ $0.fieldName == Self.answerField }),
            Set(hiddenFields.keys) == Set(Self.fieldOrder + ["hash_check"])
        else { throw .unsupportedPoll }
        var values: [String] = []
        for name in Self.fieldOrder {
            guard let value = hiddenFields[name], Self.isDigits(value) else { throw .unsupportedPoll }
            values.append(value)
        }
        guard
            let category = hiddenFields["cat"].flatMap(FlagLink.positiveInteger),
            let post = hiddenFields["numeropost"].flatMap(FlagLink.positiveInteger)
        else { throw .unsupportedPoll }
        guard options.contains(where: { $0.id == choice }) else { throw .invalidChoice }
        self.values = values
        self.topic = TopicID(category: .forum(category), topic: post)
        self.choice = choice
    }

    /// The body `W42` sent: the form's controls in document order (the token before and after the block's hidden
    /// inputs), the chosen `reponse` and the "Voter" button. HFR accepted it; another order or a body without
    /// `sondage_submit` was not tried.
    func body(token: String) -> FormBody {
        var fields: [(String, String)] = [("hash_check", token)]
        fields += zip(Self.fieldOrder, values).map { ($0, $1) }
        fields += [("hash_check", token), (Self.answerField, String(choice)), ("sondage_submit", "Voter")]
        return FormBody(fields)
    }

    /// ASCII digits only, at least one.
    private static func isDigits(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { (48...57).contains($0) }
    }
}
