import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// Posts to HFR the way its own pages do: fetch the composer's `hop` form with the account's session, fill it, submit it
/// like a browser, and report success only when HFR confirmed this very write (LOT-048, audit D3).
///
/// Every write runs in the session of the **selected** account (decision Q-8): the form is fetched and posted through
/// it, and its own `hash_check` and `pseudo` are sent (legacy Swift posted with the main account's,
/// `AccountSessionService.swift:77-105`). A POST is sent once and never retried: when its outcome is not read,
/// the flow throws `unconfirmed` (legacy: "Votre message a peut être été posté malgré tout",
/// `AddMessageViewController.m:631`).
public struct PostingFlow: Sendable {
    /// Creates the flow.
    public init() {}

    /// Fetches the write form at `url` (answer, quote, edit, new-topic or new-MP link) through `session`.
    ///
    /// The page must hold a `hop` form with a non-empty `hash_check` and `pseudo`; the token is recorded in the session.
    /// - Throws: `invalidFormURL`, `notLoggedIn`, `formUnavailable` (no form: locked topic, message not for this account),
    ///   `unsupportedForm`, `network`.
    public func loadForm(at url: URL, in session: HFRSession) async throws(PostingError) -> PostingForm {
        try await loadForm(at: url, through: session)
    }

    /// Replies with `text` through a reply or quote form (`PostingForm.Shape.reply`), topic or private message.
    public func reply(_ text: String, options: [PostOption: Bool] = [:], with form: PostingForm)
        async throws(PostingError) -> PostingResult {
        try require(form, is: .reply)
        try checkText(text)
        return try await submit(.reply, form: form, text: text, overrides: [:], options: options)
    }

    /// Starts a topic. `subcategory` is one of `form.form.subcategories`' values; nil sends the form's own choice
    /// (the selected option, else the first one, "Aucune" on `R45a`).
    public func newTopic(
        subject: String, subcategory: String? = nil, text: String, options: [PostOption: Bool] = [:], with form: PostingForm
    ) async throws(PostingError) -> PostingResult {
        try require(form, is: .newTopic)
        try checkLine(subject, as: .subject, in: form)
        try checkText(text)
        var overrides = ["sujet": subject]
        if let subcategory {
            guard form.form.subcategories.contains(where: { $0.value == subcategory }) else { throw .unknownSubcategory }
            overrides["subcat"] = subcategory
        }
        return try await submit(.newTopic, form: form, text: text, overrides: overrides, options: options)
    }

    /// Starts a private-message thread with `recipient`.
    public func newPrivateMessage(
        to recipient: String, subject: String, text: String, options: [PostOption: Bool] = [:], with form: PostingForm
    ) async throws(PostingError) -> PostingResult {
        try require(form, is: .newPrivateMessage)
        try checkLine(recipient, as: .recipient, in: form)
        try checkLine(subject, as: .subject, in: form)
        try checkText(text)
        return try await submit(
            .newPrivateMessage, form: form, text: text, overrides: ["dest": recipient, "sujet": subject], options: options
        )
    }

    /// Replaces an own message's text with `text` through its edit form; `subject` renames the thread and is accepted
    /// only on the first post, whose edit form shows the subject (`R43a`). The `delete` box is never sent.
    public func edit(
        _ text: String, subject: String? = nil, options: [PostOption: Bool] = [:], with form: PostingForm
    ) async throws(PostingError) -> PostingResult {
        try require(form, is: .edit)
        var overrides: [String: String] = [:]
        if let subject {
            guard form.form.isSubjectEditable else { throw .subjectNotEditable }
            try checkLine(subject, as: .subject, in: form)
            overrides["sujet"] = subject
        }
        try checkText(text)
        return try await submit(
            .edit, form: form, text: text, overrides: overrides, options: options, checkboxes: [PostingForm.deleteField: false]
        )
    }

    /// Deletes an own message through its edit form: the stored text sent back unchanged with the `delete` box checked
    /// (`DeleteMessageViewController.m:44`, `W16a`). On the first post of a thread this deletes the whole thread
    /// (`W19`; the other party keeps its copy of a private thread, HFR-PROTOCOL §7 X1). Pass `isFirstPost` when the topic
    /// page tells it. `confirmingWholeTopic` must be true whenever `form.requiresWholeTopicConfirmation(isFirstPost:)` is
    /// (first post by the hint or the form, or any public topic), else nothing is sent. An empty stored text is refused
    /// locally: HFR refuses an empty `content_form` (`W17a`).
    public func delete(
        with form: PostingForm, isFirstPost: Bool = false, confirmingWholeTopic: Bool = false
    ) async throws(PostingError) -> PostingResult {
        try require(form, is: .edit)
        guard form.canDelete else { throw .deleteNotOffered }
        if form.requiresWholeTopicConfirmation(isFirstPost: isFirstPost), !confirmingWholeTopic {
            throw .wholeTopicDeletionNotConfirmed
        }
        let stored = form.form.textareaContent ?? ""
        guard !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .emptyInput(.text) }
        return try await submit(
            .delete, form: form, text: stored, overrides: [:], options: [:], checkboxes: [PostingForm.deleteField: true]
        )
    }

    // MARK: - Steps

    func loadForm(at url: URL, through session: any PostingSession) async throws(PostingError) -> PostingForm {
        guard Self.isForumPage(url) else { throw .invalidFormURL }
        if Task.isCancelled { throw .network(.cancelled) }
        let response: HTTPResponse
        do {
            response = try await session.send(.get(url))
        } catch {
            throw .network(error)
        }
        // Redirects may end on another `hardware.fr` host: its token and pseudo must not be posted to the forum.
        guard Self.isForumPage(response.url) else { throw .invalidFormURL }
        let html = response.decodedText().text
        let form: ForumForm
        let layout: HopFormLayout
        do {
            form = try HopFormParser.parse(html, pageURL: response.url)
            layout = try HopFormParser.layout(html)
        } catch {
            throw Self.missingFormError(html: html, pageURL: response.url)
        }
        // The anonymous composer has the form with an empty token and pseudo (`R40b`): posting would be refused (`W17c`).
        guard
            let token = form.field(named: "hash_check")?.value, !token.isEmpty,
            let pseudo = form.field(named: "pseudo")?.value, !pseudo.isEmpty
        else { throw .notLoggedIn }
        await session.updateHashCheck(token)
        return PostingForm(form: form, layout: layout, pageURL: response.url, session: session)
    }

    func submit(
        _ action: PostingAction,
        form: PostingForm,
        text: String,
        overrides: [String: String],
        options: [PostOption: Bool],
        checkboxes: [String: Bool] = [:]
    ) async throws(PostingError) -> PostingResult {
        var boxes = checkboxes
        // Only `delete` may check the box: a composer served with it checked must not delete through another write.
        if action != .delete { boxes[PostingForm.deleteField] = false }
        for (option, checked) in options {
            guard form.form.fields.contains(where: { $0.name == option.fieldName && $0.kind == .checkbox }) else {
                throw .optionNotOffered(option)
            }
            boxes[option.fieldName] = checked
        }
        guard
            let path = form.form.action,
            let url = URL(string: path, relativeTo: HFRURL.base)?.absoluteURL,
            Self.isForumPage(url)
        else { throw .missingAction }
        let body = try PostingBody.make(
            form: form.form, layout: form.layout, text: text, overrides: overrides, checkboxes: boxes
        )
        // Nothing has left the device yet: a cancellation here is a plain failure, not an unknown outcome.
        if Task.isCancelled { throw .network(.cancelled) }
        let request = HTTPRequest.post(url, form: body, timeout: Self.postTimeout, redirectPolicy: .doNotFollow)
        let response: HTTPResponse
        do {
            response = try await form.session.send(request)
        } catch .invalidRequest(let reason) {
            throw .network(.invalidRequest(reason: reason))
        } catch {
            throw .unconfirmed(.transport(error))
        }
        return try Self.confirmation(of: action, in: response, requestURL: url, postNumber: form.postNumber)
    }

    // MARK: - Checks

    private func require(_ form: PostingForm, is shape: PostingForm.Shape) throws(PostingError) {
        guard form.shape == shape else { throw .formMismatch(expected: shape, actual: form.shape) }
    }

    private func checkText(_ text: String) throws(PostingError) {
        try checkInput(text, as: .text)
    }

    /// A subject or a recipient is a one-line text input: a browser cannot put a line break in it, and cuts it at the
    /// input's `maxlength` (counted in UTF-16 code units; `sujet` has 70 on `R43a`, `R45a`, `R45b`, `dest` none).
    private func checkLine(_ value: String, as input: PostingInput, in form: PostingForm) throws(PostingError) {
        try checkInput(value, as: input)
        guard !value.contains(where: \.isNewline) else { throw .lineBreak(input) }
        if let maximum = form.layout.maxLengths[input.fieldName], value.utf16.count > maximum {
            throw .tooLong(input, maximum: maximum)
        }
    }

    /// Refuses an empty input, and characters HFR would cut the text at (Q-3): telling the user beats a silent loss.
    private func checkInput(_ value: String, as input: PostingInput) throws(PostingError) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .emptyInput(input) }
        var refused: [Character] = []
        for character in value where character.unicodeScalars.contains(where: { $0.value > 0xFFFF }) {
            if !refused.contains(character) { refused.append(character) }
        }
        guard refused.isEmpty else { throw .unsupportedCharacters(input, refused) }
    }

    // MARK: - Helpers

    /// Legacy writes had no timeout of their own, so URLSession's 60 s applied (audit D §2); a longer wait means fewer
    /// unconfirmed outcomes.
    static let postTimeout: Double = 60

    /// An `https` page of the forum host, default port, no user info: where the session's cookies and token may go.
    static func isForumPage(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host(percentEncoded: false)?.lowercased() == HFRURL.forumHost
            && (url.port == nil || url.port == 443)
            && url.user == nil && url.password == nil
    }

    /// A page without the form: HFR's logged-out sentence means the session expired, anything else is reported with the
    /// page's own `.hop` text.
    private static func missingFormError(html: String, pageURL: URL) -> PostingError {
        let page = try? HopResponseParser.classify(html: html, context: .write, requestURL: pageURL)
        if page?.kind == .loggedOut { return .notLoggedIn }
        return .formUnavailable(message: page?.message)
    }

    /// Success needs LOT-037's confirmation (`.hop` sentence "avec succès", no link, refresh to the forum) **and** the
    /// sentence of this write: an edit answered "posted", or a reply answered "deleted", is not this write's success.
    static func confirmation(
        of action: PostingAction, in response: HTTPResponse, requestURL: URL, postNumber: Int?
    ) throws(PostingError) -> PostingResult {
        let answer: HopResponse
        do {
            answer = try HopResponseParser.classify(html: response.decodedText().text, context: .write, requestURL: requestURL)
        } catch {
            throw .unconfirmed(.unrecognizedAnswer(message: nil))
        }
        switch answer.kind {
        case .success:
            guard let message = answer.message, message == action.confirmation, let refreshURL = answer.refreshURL else {
                throw .unconfirmed(.unexpectedConfirmation(message: answer.message))
            }
            let number = action == .edit || action == .delete ? postNumber : nil
            return PostingResult(
                action: action, message: message, refreshURL: refreshURL, refreshAnchor: answer.refreshAnchor, postNumber: number
            )
        case .rejected:
            throw .rejected(message: answer.message)
        case .loggedOut:
            throw .notLoggedIn
        case .alreadyAlerted, .unrecognized:
            throw .unconfirmed(.unrecognizedAnswer(message: answer.message))
        }
    }
}
