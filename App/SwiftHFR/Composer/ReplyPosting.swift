import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRParsing
import HFRStorage

// Port of HFRswift/Swift/ReplyService.swift (ForumReplyPostingService, ReplyComposerContext) @ 2440d79. Differences: posting goes
// through HFRClient (LOT-048); success only on HFR's own sentence.
/// The topic a reply goes to, read from the page on screen.
struct ReplyTarget: Hashable, Sendable {
    /// The reply composer's page (`#repondre_form`'s link, LOT-033): `https` on the forum host.
    let formURL: URL
    /// The topic, which keys the draft.
    let topic: TopicID

    /// The draft of this topic's reply: one per topic and account, whatever the page (legacy kept one per topic,
    /// `HFRswift/Swift/AnswerView.swift:137-190`); LOT-063 asks for a constant page for that.
    var draftContext: DraftContext { .reply(topic: topic, page: 1) }
}

// Port of HFRswift/Swift/MessagesView.swift:4208-4224 (openPrivateMessageComposer) and Classes/QuoteMessageViewController.m:254-256,
// 306-330 (the "À :" field filled with the form's `dest`) @ 21173e77. Differences: the recipient stays editable (legacy Swift showed
// it read-only); drafts are kept (legacy Swift: `composerPersistsDraft = false`).
/// A new private message (LOT-128): the new-MP composer's link and the recipient it names.
struct NewMessageTarget: Hashable, Sendable {
    /// The new-MP composer (`/message.php?…cat=prive…&dest=<pseudo>`, `R45b`; the MP list's `md_btn_new_topic`, `R13a`).
    let formURL: URL
    /// The link's `dest` value, empty when it names nobody (the MP list's button, `R13a`). HFR fills the form's `dest`
    /// with it (`R45b`: `dest=user1` gives `value="user1"`), so the composer starts with it.
    let recipient: String

    /// The link's target, or nil unless it is an `https` page of the forum (default port) for a private message.
    init?(link: URL) {
        guard link.scheme == "https", link.host == HFRURL.forumHost, link.port == nil || link.port == 443,
              link.user == nil, HFRURL.category(in: link.absoluteString) == .privateMessages else { return nil }
        formURL = link
        recipient = HFRURL.queryValue(named: "dest", in: link.absoluteString) ?? ""
    }

    /// One draft per recipient named by the link and account (LOT-063 `privateMessage`): the subject and the text are
    /// kept, a recipient typed in the composer is not (a draft has no recipient field).
    var draftContext: DraftContext { .privateMessage(recipient: recipient) }
}

// Port of HFRswift/Swift/MainWindow.swift:745-757,812-835 (the "+" button and the `AnswerView(requiresSubject:requiresSubcategory:)` sheet)
// (GAP-098) and HFRswift/Swift/ReplyService.swift:96-113,392-412 (`ReplyComposerSubcategoryOption`) @ 2440d79.
// Differences: drafts are kept per forum (legacy kept one global text); the sub-category list is read from the form before the user writes.
/// A new topic (LOT-089): the forum's new-topic composer and the category that keys its draft.
struct NewTopicTarget: Hashable, Sendable {
    /// The new-topic composer (`/hfr/<cat>/nouveau_sujet.htm`, `R45a`; the list's `md_btn_new_topic`): `https` on the forum host.
    let formURL: URL
    /// The forum category, which keys the draft (LOT-063 `newTopic`).
    let forum: CategoryID

    /// The target of the list page's `md_btn_new_topic` link (`newTopicPath`) in `forum`; nil without a link, for the private
    /// messages pseudo-category (its button is the new-MP composer, LOT-128) or for a link that leaves the forum origin.
    init?(path: String?, forum: CategoryID?) {
        guard let path, let forum, case .forum = forum, let url = HFREndpoint.absoluteURL(href: path),
              url.scheme == "https", url.host == HFRURL.forumHost, url.port == nil, url.user == nil else { return nil }
        formURL = url
        self.forum = forum
    }

    /// One draft per forum and account: subject and text are kept; the sub-category is not (a draft has no such field).
    var draftContext: DraftContext { .newTopic(forum: forum) }
}

/// The sub-categories a new-topic form offers.
struct NewTopicOptions: Equatable, Sendable {
    /// Options in the form's order (`R45a`: 16, the first `value=""` "Aucune").
    let subcategories: [FormOption]
    /// What a browser would send: the option marked selected, else the first (`FormSelect.effectiveValue`).
    let preselected: String?
}

/// What a composer writes: a reply in a topic or private thread (LOT-084), a new private message (LOT-128) or a new topic
/// (LOT-089).
enum ComposerTarget: Hashable, Sendable {
    /// A reply through the page's answer link.
    case reply(ReplyTarget)
    /// A new private message through the new-MP composer.
    case newPrivateMessage(NewMessageTarget)
    /// A new topic through the forum's new-topic composer.
    case newTopic(NewTopicTarget)

    /// The draft this composer restores and saves.
    var draftContext: DraftContext {
        switch self {
        case .reply(let target): target.draftContext
        case .newPrivateMessage(let target): target.draftContext
        case .newTopic(let target): target.draftContext
        }
    }
}

/// Sends as the selected account (decision Q-8); `LiveReplyPoster` in the app, a scripted double in tests.
protocol ReplyPosting: Sendable {
    /// Fetches the composer at `formURL`, then posts `text` through it. Same contract as `PostingFlow`: a result only
    /// when HFR confirmed this reply; `unconfirmed` when it may have been posted.
    func reply(_ text: String, formURL: URL) async throws(PostingError) -> PostingResult

    /// Fetches the new-MP composer at `formURL`, then starts a thread with `recipient`. Same contract as `reply`.
    func newPrivateMessage(to recipient: String, subject: String, text: String, formURL: URL)
        async throws(PostingError) -> PostingResult

    /// Fetches the new-topic composer at `formURL` and reads its sub-category select.
    func newTopicOptions(formURL: URL) async throws(PostingError) -> NewTopicOptions

    /// Fetches the new-topic composer at `formURL` again (fresh token), then starts a topic. `subcategory` is one of the
    /// options' values. Same contract as `reply`.
    func newTopic(subject: String, subcategory: String?, text: String, formURL: URL) async throws(PostingError) -> PostingResult
}

/// LOT-048's flow in the current account's session: the form is fetched when the user sends, so its `hash_check` is
/// fresh and belongs to the session that posts (legacy fetched it at send time too, `HFRswift/Swift/ReplyService.swift:144-185`).
struct LiveReplyPoster: ReplyPosting {
    /// The current account's session (`AppEnvironment.session`).
    let session: HFRSession
    private let flow = PostingFlow()

    /// Creates a poster on `session`.
    init(session: HFRSession) {
        self.session = session
    }

    func reply(_ text: String, formURL: URL) async throws(PostingError) -> PostingResult {
        let form = try await flow.loadForm(at: formURL, in: session)
        return try await flow.reply(text, with: form)
    }

    func newPrivateMessage(to recipient: String, subject: String, text: String, formURL: URL)
        async throws(PostingError) -> PostingResult {
        let form = try await flow.loadForm(at: formURL, in: session)
        return try await flow.newPrivateMessage(to: recipient, subject: subject, text: text, with: form)
    }

    func newTopicOptions(formURL: URL) async throws(PostingError) -> NewTopicOptions {
        let form = try await flow.loadForm(at: formURL, in: session)
        guard form.shape == .newTopic else { throw .formMismatch(expected: .newTopic, actual: form.shape) }
        let select = form.form.select(named: "subcat")
        return NewTopicOptions(subcategories: form.form.subcategories, preselected: select?.effectiveValue)
    }

    func newTopic(subject: String, subcategory: String?, text: String, formURL: URL) async throws(PostingError) -> PostingResult {
        let form = try await flow.loadForm(at: formURL, in: session)
        return try await flow.newTopic(subject: subject, subcategory: subcategory, text: text, with: form)
    }
}

/// What the reply composer needs, for the current account only (nil when logged out: HFR shows no answer form then).
struct ComposerServices: Sendable {
    /// Sends through the current account's session.
    let poster: any ReplyPosting
    /// The drafts of every account (LOT-063), one store per process.
    let drafts: DraftStore
    /// The current account's key (`md_user` value), which scopes its drafts.
    let account: String
    /// The smiley favourites of every account (LOT-064), read by the smiley picker (LOT-104); not touched until it opens.
    var smileyFavorites: AppSmileyFavoritesStore = liveSmileyFavorites

    /// The single store of the app's smiley favourites (one actor per file), `Application Support/SmileyFavorites/`.
    static let liveSmileyFavorites = AppSmileyFavoritesStore(
        persistence: FileSmallStorePersistence(
            fileURL: URL.applicationSupportDirectory.appending(path: "SmileyFavorites/favorites.json")
        )
    )

    /// The single draft store of the app: one actor per file, so two stores never write it at once.
    static let liveDrafts = DraftStore(
        persistence: FileDraftPersistence(fileURL: URL.applicationSupportDirectory.appending(path: "Drafts/drafts.json"))
    )

    /// The live services of `session`, nil without an account.
    static func live(session: HFRSession, account: String?) -> ComposerServices? {
        guard let account else { return nil }
        return ComposerServices(poster: LiveReplyPoster(session: session), drafts: liveDrafts, account: account)
    }
}
