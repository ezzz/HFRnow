import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// Reports a message to the moderators with HFR's own page and form, through the selected account's session (LOT-050,
/// audit D5).
///
/// `prepare` reads the message's alert link (LOT-031): HFR either says the message was already reported or serves the
/// form (`R46`). `submit` posts the form like a browser, once, never retried, and reports a success only on HFR's own
/// confirmation sentence (`W46`, LOT-037 `.alertSubmit`, #395). The mailto fallback is the app's (LOT-135).
public struct ModeratorAlertFlow: Sendable {
    /// Creates the flow.
    public init() {}

    /// Fetches the alert page at `link` (`MessageActions.alertURL`) through `session`.
    ///
    /// A session without a usable identity (logged out, or its `md_user` expired) is `notLoggedIn` before any request.
    ///
    /// LOT-037's `.alertPrepare` classification comes first: HFR's sentence for a missing session (`R89`, `W17c`) is
    /// `notLoggedIn`; any other `.hop` with a link or an input is "already alerted" (legacy rule,
    /// `AlerteModoViewController.m:154-160`, `R88`). Otherwise the page must hold the alert form (LOT-036) with a
    /// `raison` textarea, a non-empty `hash_check`, which is recorded in the session, and an action naming the same
    /// message.
    /// - Throws: `invalidLink`, `notLoggedIn`, `formUnavailable`, `network`.
    public func prepare(link: URL, in session: HFRSession) async throws(ModeratorAlertError) -> ModeratorAlertPage {
        try await prepare(link: link, through: session)
    }

    /// Posts `form` with `reason` in `raison`, line breaks as CRLF like a browser (legacy: `\n` → `\r\n`,
    /// `AlerteModoViewController.m:210`).
    ///
    /// HFR's answer is read by LOT-037 `.alertSubmit`: its confirmation sentence (`W46`, back link, no refresh) is the
    /// only success; its logged-out sentences (`W47`, `W17c`) are `notLoggedIn`; any other `.hop` with a link or an input,
    /// or the plain-text token refusal, is `rejected`; anything else is `unconfirmed`.
    /// - Throws: `emptyReason`, `unsupportedCharacters`, `unsupportedForm`, `sessionChanged` before sending; `network` when the request
    ///   could not be sent; `notLoggedIn`, `rejected`; `unconfirmed` when the request may have left and HFR's answer was
    ///   neither its confirmation nor a refusal.
    public func submit(reason: String, with form: ModeratorAlertForm) async throws(ModeratorAlertError) -> ModeratorAlertAnswer {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .emptyReason }
        let refused = PostCharacterCheck.truncatingCharacters(in: reason)
        guard refused.isEmpty else { throw .unsupportedCharacters(refused) }
        let body: FormBody
        do throws(PostingError) {
            // `prepare` already refuses a form without a token; requiring it here again is defence in depth for a form
            // built by another path.
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
        // The form would be refused at submit anyway (`checkBeforeSending` needs the seed's identity).
        guard seed.identity != nil else { throw .notLoggedIn }
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
        let parsed = try Self.alertForm(in: html, pageURL: response.url, target: target, notice: page?.message)
        let alert = ModeratorAlertForm(
            form: parsed.form, target: target, submitURL: parsed.submitURL, layout: parsed.layout, session: session, seed: seed
        )
        guard let token = alert.form.field(named: Self.tokenField)?.value, !token.isEmpty else { throw .notLoggedIn }
        // A login adopted meanwhile holds the fresher token (#308): never overwrite it with this page's.
        await session.updateHashCheck(token, since: seed)
        return .form(alert)
    }

    /// The parts of the alert page's form that `prepare` checks before keeping it.
    private struct ParsedAlertForm {
        let form: ForumForm
        let layout: HopFormLayout
        let submitURL: URL
    }

    /// The alert form of `html`; `notice` is the page's `.hop` text, reported when there is no form.
    private static func alertForm(
        in html: String,
        pageURL: URL,
        target: ModeratorAlertTarget,
        notice: String?
    ) throws(ModeratorAlertError) -> ParsedAlertForm {
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
        return ParsedAlertForm(form: form, layout: layout, submitURL: submitURL)
    }

    /// HFR's confirmation, or why the alert is not confirmed.
    static func answer(in response: HTTPResponse, requestURL: URL) throws(ModeratorAlertError) -> ModeratorAlertAnswer {
        // Redirects are not followed: a redirect's body is not HFR's answer to the alert (`W46` is served at the action).
        guard !response.isRedirect else { throw .unconfirmed(.unrecognizedAnswer(message: nil)) }
        let page = try? HopResponseParser.classify(html: response.decodedText().text, context: .alertSubmit, requestURL: requestURL)
        switch page?.kind {
        case .success?:
            guard let message = page?.message else { throw .unconfirmed(.unrecognizedAnswer(message: nil)) }
            return ModeratorAlertAnswer(message: message)
        case .loggedOut?: throw .notLoggedIn
        case .rejected?: throw .rejected(message: page?.message)
        case .alreadyAlerted?, .unrecognized?, nil: throw .unconfirmed(.unrecognizedAnswer(message: page?.message))
        }
    }

    /// The textarea holding the user's reason (`R46`).
    static let reasonField = "raison"
    /// The form's token, sent back with the reason and recorded in the session when the form is read.
    static let tokenField = "hash_check"
}
