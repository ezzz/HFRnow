import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// Topic flags and favourites (LOT-051, audit D7): add a favourite, remove a flag, remove a favourite from the list, and
/// mark a topic read, each in the selected account's session, reporting success only when HFR confirmed it.
///
/// Every request is sent once: the transport never retries, and a failure after sending is `unconfirmed`, never a
/// success nor a plain failure. A followed link must be an `https` page of the forum with the write's exact path.
/// A write leaves only once LOT-044 confirmed the session just before it (#314): HFR answers an `addflag` sent without
/// a session with the logged-in success bytes (`P03q` = `P03a`), so its sentence alone does not prove the write.
public struct TopicFlagFlow: Sendable {
    /// What a write asks before it leaves: the health of the account session, from one GET of HFR (LOT-044).
    typealias SessionCheck = () async throws(NetworkError) -> SessionHealth

    /// The session check of the public entry points.
    private let refresh: SessionRefreshFlow

    /// Creates the flow.
    public init() {
        self.init(refresh: SessionRefreshFlow())
    }

    /// A flow whose session check is `refresh` (tests: a refresh flow with scripted probes).
    init(refresh: SessionRefreshFlow) {
        self.refresh = refresh
    }

    /// Puts the topic in the account's favourites by following a message's `addflag.php` link (a state-changing GET).
    ///
    /// Idempotent on HFR: a topic already in the favourites gets the same confirmation (`P03b`). The session is checked
    /// first (one GET of the profile page), since HFR confirms an `addflag` sent without a session too (`P03q`).
    /// - Throws: `invalidLink`, `sessionNotConfirmed`, `notLoggedIn`, `rejected`, `unconfirmed`, `network`.
    public func addFavorite(link: URL, in session: HFRSession) async throws(TopicFlagError) -> TopicFlagResult {
        try await follow(.addFavorite, link: link, through: session, after: check(session))
    }

    /// Removes the topic's flag by following a topic page's `delflag.php` link (a state-changing GET).
    ///
    /// On a favourite this also removes the topic's read flag (`P03f`). HFR never refuses it: sent again on a topic
    /// without flag it answers the same success (`P03o` = `P03n`), so a result means "no flag left", not "a flag was
    /// removed". The session is checked first, as for `addFavorite`.
    /// - Throws: `invalidLink`, `sessionNotConfirmed`, `notLoggedIn`, `rejected`, `unconfirmed`, `network`.
    public func removeFlag(link: URL, in session: HFRSession) async throws(TopicFlagError) -> TopicFlagResult {
        try await follow(.removeFlag, link: link, through: session, after: check(session))
    }

    /// Removes `topic` from the favourites the way the favourites list does: POST of `message_forum_delflags` to
    /// `manageaction.php` with the session's `hash_check` (`FavoritesTableViewController.m:1836-1858`).
    ///
    /// HFR confirms it with "Drapeaux effacés avec succès" (legacy's body, `P03j`) or "Favoris supprimés avec succès" (the
    /// browser's, `P03h`). The session is checked first, as for `addFavorite`; a valid check also records a fresh token.
    /// - Throws: `invalidTopic`, `sessionNotConfirmed`, `missingToken`, `notLoggedIn`, `rejected`, `unconfirmed`, `network`.
    public func removeFavoriteFromList(_ topic: TopicID, in session: HFRSession) async throws(TopicFlagError)
        -> TopicFlagResult {
        try await removeFavoriteFromList(topic, through: session, after: check(session))
    }

    /// Marks `topic` read up to `page` by reading that page with the account's session, as legacy did with the last
    /// page (`Favorites.swift:44-47`, `FavoritesTableViewController.m:1602-1607`; HFR-PROTOCOL §7 E25).
    ///
    /// The mark is reported only when HFR served that topic's page to a logged-in account (its answer form carries a
    /// token, which is recorded in the session).
    /// - Throws: `invalidTopic`, `unconfirmed`, `network`.
    public func markRead(_ topic: TopicID, page: Int, in session: HFRSession) async throws(TopicFlagError) -> TopicReadMark {
        try await markRead(topic, page: page, through: session)
    }

    // MARK: - Steps

    /// `follow`, sent only when `check` says the account session is valid; an invalid link asks nothing.
    func follow(
        _ action: TopicFlagAction, link: URL, through session: any FlagSession, after check: SessionCheck
    ) async throws(TopicFlagError) -> TopicFlagResult {
        guard let path = action.linkPath, FlagLink(link, path: path) != nil else { throw .invalidLink }
        try await Self.confirm(check)
        return try await follow(action, link: link, through: session)
    }

    /// `removeFavoriteFromList`, sent only when `check` says the account session is valid; an invalid topic asks nothing.
    func removeFavoriteFromList(
        _ topic: TopicID, through session: any FlagSession, after check: SessionCheck
    ) async throws(TopicFlagError) -> TopicFlagResult {
        guard case .forum(let category) = topic.category, category > 0, topic.topic > 0 else { throw .invalidTopic }
        try await Self.confirm(check)
        return try await removeFavoriteFromList(topic, through: session)
    }

    func follow(_ action: TopicFlagAction, link: URL, through session: any FlagSession) async throws(TopicFlagError)
        -> TopicFlagResult {
        guard let path = action.linkPath, let flagLink = FlagLink(link, path: path) else { throw .invalidLink }
        // A redirect is not followed: HFR answers these GETs in place (`P03a`, `P03d`), anything else is not its confirmation.
        let request = HTTPRequest.get(flagLink.url, redirectPolicy: .doNotFollow)
        let response = try await exchange(request, through: session)
        return try Self.confirmation(of: action, topic: flagLink.topic, in: response, requestURL: flagLink.url)
    }

    func removeFavoriteFromList(_ topic: TopicID, through session: any FlagSession) async throws(TopicFlagError)
        -> TopicFlagResult {
        guard case .forum(let category) = topic.category, category > 0, topic.topic > 0 else { throw .invalidTopic }
        guard let token = await session.hashCheck else { throw .missingToken }
        let request = HTTPRequest.post(
            Self.manageActionURL, form: Self.removalBody(topic: topic.topic, category: category, token: token),
            redirectPolicy: .doNotFollow
        )
        let response = try await exchange(request, through: session)
        return try Self.confirmation(of: .removeFavoriteFromList, topic: topic, in: response, requestURL: Self.manageActionURL)
    }

    func markRead(_ topic: TopicID, page: Int, through session: any FlagSession) async throws(TopicFlagError)
        -> TopicReadMark {
        guard case .forum(let category) = topic.category, category > 0, topic.topic > 0, page >= 1 else {
            throw .invalidTopic
        }
        let request: HTTPRequest
        do {
            request = try HFREndpoint.topicPage(topic: topic, page: page)
        } catch {
            throw .invalidTopic
        }
        let response = try await exchange(request, through: session)
        // The session follows redirects to any `hardware.fr` host (LOT-042): only a forum page can be this topic's.
        guard PostingFlow.isForumPage(response.url) else { throw .unconfirmed(.unrecognizedAnswer(message: nil)) }
        let html = response.decodedText().text
        guard
            let metadata = try? TopicPageMetadataParser.parse(html: html, pageURL: response.url.absoluteString),
            metadata.topicID == topic,
            let token = metadata.answerFormFields["hash_check"], !token.isEmpty
        else {
            // An anonymous page (`R20`), another topic or a message page: the account's flag was not moved.
            throw .unconfirmed(.unrecognizedAnswer(message: Self.hopMessage(in: html, requestURL: response.url)))
        }
        await session.updateHashCheck(token)
        return TopicReadMark(topic: topic, page: metadata.currentPage, pageCount: metadata.maxPage, pageURL: response.url)
    }

    // MARK: - Helpers

    /// The entry points' check: LOT-044's refresh of `session`, which also merges the cookies and token HFR sends back.
    private func check(_ session: HFRSession) -> SessionCheck {
        let refresh = self.refresh
        return { () async throws(NetworkError) -> SessionHealth in try await refresh.refresh(session) }
    }

    /// Lets a write leave only after a `valid` session check; a check that could not be done is a `network` failure.
    private static func confirm(_ check: SessionCheck) async throws(TopicFlagError) {
        if Task.isCancelled { throw .network(.cancelled) }
        let health: SessionHealth
        do throws(NetworkError) {
            health = try await check()
        } catch {
            throw .network(error)
        }
        guard health == .valid else { throw .sessionNotConfirmed(health) }
    }

    /// Sends `request` once. Before it leaves the device a failure is `network`; after, HFR may have acted: `unconfirmed`.
    private func exchange(_ request: HTTPRequest, through session: any FlagSession) async throws(TopicFlagError)
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

    /// The list's form action (`P03c`, `R10`; legacy `FavoritesTableViewController.m:1841`).
    static let manageActionURL: URL = {
        guard let url = URL(string: "https://forum.hardware.fr/modo/manageaction.php?config=hfr.inc&cat=0&type_page=forum1f&moderation=0")
        else { preconditionFailure("The manageaction URL literal is valid") }
        return url
    }()

    /// Legacy's body, fields in its order (`FavoritesTableViewController.m:1846-1858`): one topic at index 0, the list's
    /// end marker at index 1, as the favourites form writes it for a one-row list (`P03c`).
    static func removalBody(topic: Int, category: Int, token: String) -> FormBody {
        FormBody([
            ("hash_check", token),
            ("topic1", "-1"),
            ("topic_statusno1", "-1"),
            ("action_reaction", "message_forum_delflags"),
            ("type_page", "forum1f"),
            ("topic0", String(topic)),
            ("valuecat0", String(category)),
            ("valueforum0", "hardwarefr")
        ])
    }

    /// Success needs LOT-037's confirmation **and** one of this write's own sentences: `W18` (mark unread) and `P03d`
    /// (flag removed) are confirmations too, of other writes.
    static func confirmation(
        of action: TopicFlagAction, topic: TopicID, in response: HTTPResponse, requestURL: URL
    ) throws(TopicFlagError) -> TopicFlagResult {
        guard !response.isRedirect else { throw .unconfirmed(.unrecognizedAnswer(message: nil)) }
        let answer: HopResponse
        do {
            answer = try HopResponseParser.classify(html: response.decodedText().text, context: .write, requestURL: requestURL)
        } catch {
            throw .unconfirmed(.unrecognizedAnswer(message: nil))
        }
        switch answer.kind {
        case .success:
            guard let message = answer.message, let refreshURL = answer.refreshURL else {
                throw .unconfirmed(.unrecognizedAnswer(message: answer.message))
            }
            guard action.confirmations.contains(message) else { throw .unconfirmed(.unexpectedConfirmation(message: message)) }
            return TopicFlagResult(action: action, topic: topic, message: message, refreshURL: refreshURL)
        case .rejected:
            throw .rejected(message: answer.message)
        case .loggedOut:
            throw .notLoggedIn
        case .alreadyAlerted, .unrecognized:
            throw .unconfirmed(.unrecognizedAnswer(message: answer.message))
        }
    }

    /// The `.hop` sentence of a page that is not the expected one, to show the user what HFR said.
    private static func hopMessage(in html: String, requestURL: URL) -> String? {
        (try? HopResponseParser.classify(html: html, context: .write, requestURL: requestURL))?.message
    }
}
