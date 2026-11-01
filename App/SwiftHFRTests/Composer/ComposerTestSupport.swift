import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Synchronization

/// The answer link of `readerTopic` as HFR prints it in `#repondre_form` (`R61d`, other topic numbers).
let replyFormURL = url(
    "https://forum.hardware.fr/message.php?config=hfr.inc&cat=13&post=28563&page=5&p=1&subcat=0&sondage=0&owntopic=0&new=0"
)

let replyTarget = ReplyTarget(formURL: replyFormURL, topic: readerTopic)

/// HFR's confirmation of a reply (`W30`, HFR-PROTOCOL §7 E15).
let replyConfirmed = PostingResult(
    action: .reply, message: "Votre réponse a été postée avec succès !",
    refreshURL: url("https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm#bas"), refreshAnchor: "bas"
)

/// Answers each reply with the next scripted outcome and records what was sent.
final class ScriptedPoster: ReplyPosting {
    struct Call: Equatable, Sendable {
        let text: String
        let formURL: URL
    }

    private let state: Mutex<(outcomes: [Result<PostingResult, PostingError>], calls: [Call])>
    /// Suspends every reply until opened, when set.
    let gate: ReaderGate?

    init(_ outcomes: [Result<PostingResult, PostingError>], gate: ReaderGate? = nil) {
        state = Mutex((outcomes, []))
        self.gate = gate
    }

    var calls: [Call] { state.withLock { $0.calls } }

    func reply(_ text: String, formURL: URL) async throws(PostingError) -> PostingResult {
        let outcome = state.withLock { state in
            state.calls.append(Call(text: text, formURL: formURL))
            return state.outcomes.isEmpty ? .failure(.network(.unscripted)) : state.outcomes.removeFirst()
        }
        await gate?.wait()
        return try outcome.get()
    }
}

/// In-memory draft file that counts writes and can be made to fail like a full disk.
final class CountingDraftPersistence: DraftPersistence {
    private struct State {
        var document: DraftDocument?
        var saves = 0
        var failSaves = false
    }

    private let state = Mutex(State())

    var saves: Int { state.withLock { $0.saves } }

    func failSaves(_ fail: Bool) { state.withLock { $0.failSaves = fail } }

    func load() throws -> DraftDocument? { state.withLock { $0.document } }

    func save(_ document: DraftDocument) throws {
        try state.withLock { state in
            if state.failSaves { throw CocoaError(.fileWriteOutOfSpace) }
            state.document = document
            state.saves += 1
        }
    }

    func quarantineUnreadableData() throws {}
}

/// A draft file that cannot be read (I/O failure, not a format problem): the store then refuses every write until
/// `reload()`, which the composer never calls.
struct UnreadableDraftPersistence: DraftPersistence {
    func load() throws -> DraftDocument? { throw CocoaError(.fileReadNoPermission) }
    func save(_ document: DraftDocument) throws {}
    func quarantineUnreadableData() throws {}
}

enum ComposerFixture {
    static let account = "user1"

    static func services(
        poster: any ReplyPosting, drafts: DraftStore = DraftStore(persistence: InMemoryDraftPersistence()), account: String = account
    ) -> ComposerServices {
        ComposerServices(poster: poster, drafts: drafts, account: account)
    }

    @MainActor
    static func model(
        poster: any ReplyPosting, drafts: DraftStore = DraftStore(persistence: InMemoryDraftPersistence()),
        autosaveDelay: Duration = .seconds(60)
    ) -> ReplyComposerModel {
        ReplyComposerModel(target: replyTarget, services: services(poster: poster, drafts: drafts), autosaveDelay: autosaveDelay)
    }

    /// The stored draft text of the reply context for `account`, nil when there is none.
    static func storedText(_ drafts: DraftStore, account: String = account) async -> String? {
        await drafts.draft(for: replyTarget.draftContext, account: account)?.text
    }
}
