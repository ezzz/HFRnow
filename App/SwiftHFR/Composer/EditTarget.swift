import Foundation
import HFRModels
import HFRParsing
import HFRStorage

// Port of HFRswift/Swift/MessagesView.swift (`openEditComposer`, `:3525-3531`; `prefillComposer`, `:3549-3576`) @ 2440d79, and of the
// `subcat` and `sujet` handling of Classes/QuoteMessageViewController.m:249-290 @ 2440d79. Differences: GAP-096; the edit form is read
// whole, so a first post also edits its subject and sub-category, as the ObjC composer did and the Swift one no longer did.
/// An own message to edit or delete (LOT-088): the edit link of its toolbar (LOT-031) and the topic and message it must name.
struct EditTarget: Hashable, Sendable {
    /// The edit form's page: `https` on the forum host.
    let formURL: URL
    /// The topic on screen.
    let topic: TopicID
    /// The message (`numreponse`).
    let post: Int

    /// The target of the edit `link` of message `post` in `topic`; nil for a link that leaves the forum origin (same rule as
    /// `PostingFlow`) or names another topic or message: the form it serves is posted back as is.
    init?(link: URL?, post: Int, topic: TopicID?) {
        guard let link, let topic, link.scheme == "https", link.host == HFRURL.forumHost, [nil, 443].contains(link.port), link.user == nil,
              HFRURL.topicID(in: link.absoluteString) == topic, HFRURL.numreponse(in: link.absoluteString) == post else { return nil }
        formURL = link
        self.topic = topic
        self.post = post
    }

    /// One draft per message and account (LOT-063 `edit`): it never touches the topic's reply draft.
    var draftContext: DraftContext { .edit(topic: topic, post: post) }
}

/// What an edit form serves for the composer to open on.
struct EditPrefill: Equatable, Sendable {
    /// The stored text. HFR serves it without a leading line break the message may hold (`R130b`), so an edit sent back
    /// unchanged loses that one, whatever the client.
    let text: String
    /// The thread's title on a first post (a visible `sujet`, `R63b`, `R43a`); nil on a later post, whose `sujet` is hidden (`R62a`).
    let subject: String?
    /// The `subcat` select of a public first post (`R63b`), its option marked `selected` preselected; nil when the form has none
    /// (a later post sends its hidden `subcat`, `R62a`, a private thread has neither, `R43a`).
    let subcategories: NewTopicOptions?
}

extension EditPrefill {
    /// Reads `form`. The legacy composer read the same fields (`QuoteMessageViewController.m:249-290`).
    init(form: ForumForm) {
        text = form.textareaContent ?? ""
        subject = form.isSubjectEditable ? form.field(named: "sujet")?.value ?? "" : nil
        let select = form.select(named: "subcat")
        subcategories = select.map { NewTopicOptions(subcategories: form.subcategories, preselected: $0.effectiveValue) }
    }
}
