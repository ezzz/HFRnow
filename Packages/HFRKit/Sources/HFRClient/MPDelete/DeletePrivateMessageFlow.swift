import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// Deletes an MP thread from the selected account's list (LOT-094), the way the MP list does: one POST of
/// `valid_eff_prive` to `manageaction.php` with the session's `hash_check` (legacy `MPListView.swift:114-159` @ 03e5e22).
///
/// HFR removes the thread from the deleting account's list only: the other participants keep it until they delete it
/// too (`R95k`, `W65`). Success is reported only on HFR's own confirmation (`W64`, `W65`). The request is sent once and
/// never retried; a failure after sending is `unconfirmed`. The write leaves only once LOT-044 confirmed the session just
/// before it (#314) and no login landed in this session meanwhile (#340, #342).
public struct DeletePrivateMessageFlow: Sendable {
    /// What the delete asks before it leaves: the health of the account session, from one GET of HFR (LOT-044).
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

    /// Deletes the MP thread `thread` (category `.privateMessages`, its `post` number) from the account's MP list.
    ///
    /// The session is checked first (one GET of the profile page), which also records a fresh token; the POST carries
    /// the token the session holds after that check.
    /// - Throws: `invalidThread`, `sessionNotConfirmed`, `sessionChanged`, `missingToken`, `notLoggedIn`, `rejected`,
    ///   `unconfirmed`, `network`.
    public func delete(_ thread: TopicID, in session: HFRSession) async throws(MPThreadDeleteError) -> MPThreadDeletion {
        let refresh = self.refresh
        return try await delete(thread, through: session) { () async throws(NetworkError) -> SessionHealth in
            try await refresh.refresh(session)
        }
    }

    // MARK: - Steps

    /// `delete`, sent only when `check` says the account session is valid and the session kept the account and the
    /// login it had before the check; an invalid thread asks nothing.
    func delete(
        _ thread: TopicID, through session: any PostingSession, after check: SessionCheck
    ) async throws(MPThreadDeleteError) -> MPThreadDeletion {
        guard Self.isThread(thread) else { throw .invalidThread }
        if Task.isCancelled { throw .network(.cancelled) }
        let before = await session.hashCheckSeed()
        let health: SessionHealth
        do throws(NetworkError) {
            health = try await check()
        } catch {
            throw .network(error)
        }
        guard health == .valid else { throw .sessionNotConfirmed(health) }
        if Task.isCancelled { throw .network(.cancelled) }
        // Identity, generation and token in one actor turn: the token sent is the one of the account the check confirmed.
        // A login landing after this read and before the POST leaves (one actor hop) would send this account's token with
        // the other cookies, which HFR refuses with its bad-token answer (`W64x`): nothing is deleted then.
        let after = await session.hashCheckSeed()
        guard let identity = before.identity, after.identity == identity, after.loginGeneration == before.loginGeneration
        else { throw .sessionChanged }
        guard let token = after.hashCheck else { throw .missingToken }
        return try await send(thread, token: token, through: session)
    }

    /// The POST itself, with `token`; no session check (tests of the request and of the answers).
    func send(_ thread: TopicID, token: String, through session: any PostingSession) async throws(MPThreadDeleteError)
        -> MPThreadDeletion {
        guard Self.isThread(thread) else { throw .invalidThread }
        if Task.isCancelled { throw .network(.cancelled) }
        let request = HTTPRequest.post(
            Self.manageActionURL, form: Self.body(thread: thread.topic, token: token), redirectPolicy: .doNotFollow
        )
        let response: HTTPResponse
        do {
            response = try await session.send(request)
        } catch .invalidRequest(let reason) {
            throw .network(.invalidRequest(reason: reason))
        } catch {
            throw .unconfirmed(.transport(error))
        }
        return try Self.confirmation(for: thread, in: response)
    }

    // MARK: - Request

    /// The MP list's form action (`R95k` `form1`; legacy `MPListView.swift:127-140` @ 03e5e22).
    static let manageActionURL: URL = {
        guard
            let url = URL(string: "https://forum.hardware.fr/modo/manageaction.php?config=hfr.inc&cat=prive&type_page=forum1&moderation=0")
        else { preconditionFailure("The manageaction URL literal is valid") }
        return url
    }()

    /// Legacy's fields (`MPListView.swift:145-154` @ 03e5e22) in the order `W64` and `W65` sent them: one thread at
    /// index 0, the end marker at index 1. Legacy encoded a Swift dictionary, whose order is not fixed.
    static func body(thread: Int, token: String) -> FormBody {
        FormBody([
            ("hash_check", token),
            ("topic0", String(thread)),
            ("valuecat0", "prive"),
            ("valueforum0", "hardwarefr"),
            ("topic1", "-1"),
            ("topic_statusno1", "-1"),
            ("action_reaction", "valid_eff_prive"),
            ("type_page", "forum1")
        ])
    }

    /// An MP thread number: the private-messages category and a positive `post`.
    private static func isThread(_ thread: TopicID) -> Bool {
        thread.category == .privateMessages && thread.topic > 0
    }

    // MARK: - Answer

    /// HFR's sentence after a thread delete (`W64` by the owner, `W65` by the recipient).
    static let confirmationSentence = "Action effectuée avec succès"

    /// Success needs LOT-037's confirmation, this write's whole sentence (which names no action, so it is generic) and a
    /// refresh to the MP list (`/forum1.php` with `cat=prive`, `W64`, `W65`): another write's confirmation is not this one.
    static func confirmation(for thread: TopicID, in response: HTTPResponse) throws(MPThreadDeleteError) -> MPThreadDeletion {
        guard !response.isRedirect else { throw .unconfirmed(.unrecognizedAnswer(message: nil)) }
        let answer: HopResponse
        do {
            answer = try HopResponseParser.classify(
                html: response.decodedText().text, context: .write, requestURL: manageActionURL
            )
        } catch {
            throw .unconfirmed(.unrecognizedAnswer(message: nil))
        }
        switch answer.kind {
        case .success:
            guard let message = answer.message, let refreshURL = answer.refreshURL else {
                throw .unconfirmed(.unrecognizedAnswer(message: answer.message))
            }
            guard message == confirmationSentence, isPrivateMessageList(refreshURL) else {
                throw .unconfirmed(.unexpectedConfirmation(message: message))
            }
            return MPThreadDeletion(thread: thread, message: message, refreshURL: refreshURL)
        case .rejected:
            throw .rejected(message: answer.message)
        case .loggedOut:
            throw .notLoggedIn
        case .alreadyAlerted, .unrecognized:
            throw .unconfirmed(.unrecognizedAnswer(message: answer.message))
        }
    }

    /// The MP list page HFR refreshes to after the delete: `/forum1.php` of the forum with exactly one `cat=prive`.
    static func isPrivateMessageList(_ url: URL) -> Bool {
        guard
            url.scheme == "https", url.host == "forum.hardware.fr", url.path == "/forum1.php",
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return false }
        return items.filter { $0.name == "cat" }.map(\.value) == ["prive"]
    }
}
