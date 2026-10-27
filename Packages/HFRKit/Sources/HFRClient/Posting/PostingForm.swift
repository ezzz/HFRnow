import Foundation
import HFRModels
import HFRParsing

/// A write form fetched through one account's session, ready to be filled and submitted through that same session.
///
/// It keeps the session that fetched it, so the form's `hash_check` and `pseudo` (the selected account's, echoed by
/// HFR) always travel with that account's cookies: a form cannot be submitted as another account (decision Q-8).
public struct PostingForm: Sendable {
    /// Which composer HFR served, read from the form itself.
    public enum Shape: String, Sendable, Hashable {
        /// Reply or quote composer of a topic or a private-message thread (`R40a`, `R41a`, `R47b`).
        case reply
        /// New-topic composer: visible `sujet`, usually a `subcat` select (`R45a`).
        case newTopic
        /// New private-message composer: visible `sujet` and a `dest` field (`R45b`).
        case newPrivateMessage
        /// Edit form of an existing message: a non-empty `numreponse` (`R43a`-`R44`).
        case edit
    }

    /// The parsed form: subject, recipient, sub-categories, prefilled text (quote or edit), favourite smileys.
    public let form: ForumForm
    /// The composer the form belongs to.
    public let shape: Shape
    /// The URL the form was served from, after redirects.
    public let pageURL: URL
    let layout: HopFormLayout
    let session: any PostingSession

    init(form: ForumForm, layout: HopFormLayout, pageURL: URL, session: any PostingSession) {
        self.form = form
        self.layout = layout
        self.pageURL = pageURL
        self.session = session
        self.shape = Self.shape(of: form)
    }

    /// True when the edit form offers to delete the message (its `delete` box; absent on another account's message, `R44`).
    public var canDelete: Bool {
        form.fields.contains { $0.name == Self.deleteField && $0.kind == .checkbox }
    }

    /// True when the form itself says that deleting through it deletes the whole thread: the first post of a thread
    /// has a visible subject and its box reads "Effacer l'intégralité du sujet" (`R43a`; a later post: hidden subject,
    /// "Effacer ce message", `R43b`). Either sign is enough. These signs are verified on private messages only: for a
    /// public topic (pending capture) use `requiresWholeTopicConfirmation(isFirstPost:)`, which fails closed.
    public var deletesWholeTopic: Bool {
        guard shape == .edit, canDelete else { return false }
        let label = layout.checkboxLabels[Self.deleteField]?.lowercased() ?? ""
        return form.isSubjectEditable || label.contains("intégralité")
    }

    /// True when the form belongs to a private-message thread (its hidden `cat` is `prive`, `R43a`-`R47u1`).
    public var isPrivateThread: Bool {
        form.field(named: "cat")?.value == "prive"
    }

    /// True when a delete through this form must be confirmed as a whole-thread delete: the caller knows the message is
    /// the first post (`isFirstPost`, from the topic page), the form says so (`deletesWholeTopic`), or the thread is not
    /// a private one. The first-post signs of a public topic's edit form are not captured, so every public delete is
    /// treated as possibly deleting the topic until they are (fail closed).
    public func requiresWholeTopicConfirmation(isFirstPost: Bool = false) -> Bool {
        isFirstPost || deletesWholeTopic || !isPrivateThread
    }

    /// `numreponse` of the message an edit form belongs to.
    var postNumber: Int? {
        form.field(named: "numreponse").flatMap { Int($0.value) }
    }

    static let deleteField = "delete"

    /// An edit form names its message (`numreponse`); a composer with a visible subject starts a thread, with a
    /// recipient field a private one. Reply, quote and multi-quote composers have none of these (`R40a`-`R47u1`).
    private static func shape(of form: ForumForm) -> Shape {
        if let number = form.field(named: "numreponse")?.value, !number.isEmpty { return .edit }
        guard form.isSubjectEditable else { return .reply }
        return form.field(named: "dest") == nil ? .newTopic : .newPrivateMessage
    }
}
