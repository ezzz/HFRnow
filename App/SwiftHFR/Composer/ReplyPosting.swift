import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRStorage

/// The topic a reply goes to, read from the page on screen.
struct ReplyTarget: Hashable, Sendable {
    /// The reply composer's page (`#repondre_form`'s link, LOT-033): `https` on the forum host.
    let formURL: URL
    /// The topic, which keys the draft.
    let topic: TopicID
    /// Topic title, for the sheet's title.
    let title: String

    /// The draft of this topic's reply: one per topic and account, whatever the page (legacy kept one per topic,
    /// `HFRswift/Swift/AnswerView.swift:137-190`); LOT-063 asks for a constant page for that.
    var draftContext: DraftContext { .reply(topic: topic, page: 1) }
}

/// Sends a reply as the selected account (decision Q-8); `LiveReplyPoster` in the app, a scripted double in tests.
protocol ReplyPosting: Sendable {
    /// Fetches the composer at `formURL`, then posts `text` through it. Same contract as `PostingFlow`: a result only
    /// when HFR confirmed this reply; `unconfirmed` when it may have been posted.
    func reply(_ text: String, formURL: URL) async throws(PostingError) -> PostingResult
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
}

/// What the reply composer needs, for the current account only (nil when logged out: HFR shows no answer form then).
struct ComposerServices: Sendable {
    /// Sends through the current account's session.
    let poster: any ReplyPosting
    /// The drafts of every account (LOT-063), one store per process.
    let drafts: DraftStore
    /// The current account's key (`md_user` value), which scopes its drafts.
    let account: String

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
