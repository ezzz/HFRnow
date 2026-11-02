import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// Reports a message to the moderators with HFR's own page and form, through the selected account's session (LOT-050,
/// audit D5).
///
/// `prepare` reads the message's alert link (LOT-031): HFR either says the message was already reported or serves the
/// form (`R46`). `submit` posts the form like a browser, once, never retried. HFR's answer to it is not read until #395,
/// so it is never reported as a success: the app shows HFR's own sentence. The mailto fallback is the app's (LOT-135).
public struct ModeratorAlertFlow: Sendable {
    /// Creates the flow.
    public init() {}

    /// Fetches the alert page at `link` (`MessageActions.alertURL`) through `session`.
    ///
    /// LOT-037's `.alertPrepare` classification comes first: a `.hop` with a link or an input is "already alerted"
    /// (legacy rule, `AlerteModoViewController.m:154-160`). Otherwise the page must hold the alert form (LOT-036) with a
    /// `raison` textarea, a non-empty `hash_check`, which is recorded in the session, and an action naming the same
    /// message.
    /// - Throws: `invalidLink`, `notLoggedIn`, `formUnavailable`, `network`.
    public func prepare(link: URL, in session: HFRSession) async throws(ModeratorAlertError) -> ModeratorAlertPage {
        try await prepare(link: link, through: session)
    }

    /// Posts `form` with `reason` in `raison`, line breaks as CRLF like a browser (legacy: `\n` → `\r\n`,
    /// `AlerteModoViewController.m:210`).
    ///
    /// Every answer HFR gives with a sentence comes back as `ModeratorAlertAnswer`, whether LOT-037 would read it as a
    /// refusal or not: HFR's success page has a back link (`W46`), so it would otherwise read as a refusal and invite a
    /// second alert (its reading is #395). Only HFR's logged-out sentence (`W17c`) is read: it is `notLoggedIn`.
    /// - Throws: `emptyReason`, `unsupportedCharacters`, `unsupportedForm`, `sessionChanged` before sending; `network` when the request
    ///   could not be sent; `notLoggedIn`; `unconfirmed` when the request may have left and no sentence was read.
    public func submit(reason: String, with form: ModeratorAlertForm) async throws(ModeratorAlertError) -> ModeratorAlertAnswer {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .emptyReason }
        let refused = PostCharacterCheck.truncatingCharacters(in: reason)
        guard refused.isEmpty else { throw .unsupportedCharacters(refused) }
        let body: FormBody
        do throws(PostingError) {
            body = try PostingBody.make(
                form: form.form, layout: form.layout, text: reason, textField: Self.reasonField, requiredFields: [Self.tokenField]
            )
        } catch .unsupportedForm(let cause) {
            throw .unsupportedForm(reason: cause)
        } catch {
            // Not reached: `PostingBody.make` throws only `unsupportedForm`; the typed catch must still be exhaustive.
            throw .unsupportedForm(reason: "body")
        }
        try await Self.checkBeforeSending(form)
        let request = HTTPRequest.post(form.submitURL, form: body, timeout: PostingFlow.postTimeout, redirectPolicy: .doNotFollow)
        let response: HTTPResponse
        do {
            response = try await form.session.send(request)
        } catch .invalidRequest(let reason) {
            throw .network(.invalidRequest(reason: reason))
        } catch {
            throw .unconfirmed(.transport(error))
        }
        return try Self.answer(in: response, requestURL: form.submitURL)
    }

    // MARK: - Steps

    /// Last check before the POST: nothing has left the device yet, so a cancellation is a plain failure, not an unknown
    /// outcome. It wins over a changed session, and is checked again after the identity lookup's suspension.
    ///
    /// The form's token belongs to the account it was read with: after a logout or a login of another account in this
    /// session, say so before sending (#342). A re-login of the same account keeps the form usable, as for posts: the
    /// seed's identity is compared, not its login generation.
    private static func checkBeforeSending(_ form: ModeratorAlertForm) async throws(ModeratorAlertError) {
        if Task.isCancelled { throw .network(.cancelled) }
        let current = await form.session.userKey(now: Date())
        if Task.isCancelled { throw .network(.cancelled) }
        guard let identity = form.seed.identity, current == identity else { throw .sessionChanged }
    }

    func prepare(link: URL, through session: any PostingSession) async throws(ModeratorAlertError) -> ModeratorAlertPage {
        guard let target = ModeratorAlertTarget(link) else { throw .invalidLink }
        if Task.isCancelled { throw .network(.cancelled) }
        let seed = await session.hashCheckSeed()
        let response: HTTPResponse
        do {
            response = try await session.send(.get(link))
        } catch {
            throw .network(error)
        }
        // Redirects may end on another `hardware.fr` host: its token must not be posted to the forum.
        guard PostingFlow.isForumPage(response.url) else { throw .invalidLink }
        let html = response.decodedText().text
        let page = try? HopResponseParser.classify(html: html, context: .alertPrepare, requestURL: response.url)
        switch page?.kind {
        case .alreadyAlerted?: return .alreadyAlerted(message: page?.message)
        case .loggedOut?: throw .notLoggedIn
        default: break
        }
        let alert = try Self.alertForm(
            in: html, pageURL: response.url, target: target, notice: page?.message, session: session, seed: seed
        )
        guard let token = alert.form.field(named: Self.tokenField)?.value, !token.isEmpty else { throw .notLoggedIn }
        // A login adopted meanwhile holds the fresher token (#308): never overwrite it with this page's.
        await session.updateHashCheck(token, since: seed)
        return .form(alert)
    }

    /// The alert form of `html`; `notice` is the page's `.hop` text, reported when there is no form.
    private static func alertForm(
        in html: String,
        pageURL: URL,
        target: ModeratorAlertTarget,
        notice: String?,
        session: any PostingSession,
        seed: HashCheckSeed
    ) throws(ModeratorAlertError) -> ModeratorAlertForm {
        let form: ForumForm
        let layout: HopFormLayout
        do {
            form = try HopFormParser.parseModerationForm(html, pageURL: pageURL)
            layout = try HopFormParser.moderationLayout(html)
        } catch {
            throw .formUnavailable(message: notice)
        }
        guard layout.controls.contains(.textarea(name: reasonField, isDisabled: false)) else {
            throw .formUnavailable(message: notice)
        }
        // The action is posted with the account's cookies and token: it must be the alert page of this very message.
        guard
            let action = form.action,
            let submitURL = URL(string: action, relativeTo: HFRURL.base)?.absoluteURL,
            ModeratorAlertTarget(submitURL) == target
        else { throw .invalidLink }
        return ModeratorAlertForm(form: form, target: target, submitURL: submitURL, layout: layout, session: session, seed: seed)
    }

    /// HFR's sentence, or why there is none to show.
    static func answer(in response: HTTPResponse, requestURL: URL) throws(ModeratorAlertError) -> ModeratorAlertAnswer {
        let page = try? HopResponseParser.classify(html: response.decodedText().text, context: .write, requestURL: requestURL)
        if page?.kind == .loggedOut { throw .notLoggedIn }
        guard let message = page?.message else { throw .unconfirmed(.unrecognizedAnswer(message: nil)) }
        return ModeratorAlertAnswer(message: message)
    }

    /// The textarea holding the user's reason (`R46`).
    static let reasonField = "raison"
    /// The form's token, sent back with the reason and recorded in the session when the form is read.
    static let tokenField = "hash_check"
}
