import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// #1179: "Vider" deletes every archived draft of the topic at once, so it asks first (HIG: a destructive action is confirmed,
/// its button names the action). Legacy `AnswerView.swift:1936-1941` @ 87fe0d1c deleted without asking: a deliberate difference.
@MainActor
struct ArchivedDraftsClearConfirmationTests {
    private func composerWithDrafts(_ texts: [String]) async throws -> ReplyComposerModel {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        for text in texts {
            try await drafts.archiveReply(text, topic: replyTarget.topic, source: .quickReply, account: ComposerFixture.account)
        }
        let composer = ComposerFixture.model(poster: ScriptedPoster([]), drafts: drafts)
        await composer.start()
        return composer
    }

    @Test func askingDeletesNothingUntilItIsConfirmed() async throws {
        let composer = try await composerWithDrafts(["a", "b"])
        let confirmation = ArchivedClearConfirmation()
        confirmation.request()
        #expect(confirmation.isAsking)
        #expect(composer.archivedDrafts.count == 2)
    }

    @Test func confirmingDeletesEveryArchivedDraftAndCloses() async throws {
        let composer = try await composerWithDrafts(["a", "b"])
        let confirmation = ArchivedClearConfirmation()
        confirmation.request()
        await confirmation.confirm(discardingIn: composer)
        #expect(composer.archivedDrafts.isEmpty)
        #expect(!confirmation.isAsking)
    }

    @Test func cancellingKeepsTheDraftsAndCloses() async throws {
        let composer = try await composerWithDrafts(["a", "b"])
        let confirmation = ArchivedClearConfirmation()
        confirmation.request()
        confirmation.cancel()
        #expect(!confirmation.isAsking)
        #expect(composer.archivedDrafts.count == 2)
    }

    @Test func aConfirmWithoutARequestDeletesNothing() async throws {
        let composer = try await composerWithDrafts(["a"])
        await ArchivedClearConfirmation().confirm(discardingIn: composer)
        #expect(composer.archivedDrafts.count == 1)
    }

    @Test func theWordingNamesTheActionAndCountsWhatIsDeleted() {
        #expect(ArchivedDraftsFormat.clearConfirmQuestion == "Vider les brouillons ?")
        #expect(ArchivedDraftsFormat.clearConfirmTitle == "Supprimer les brouillons")
        #expect(ArchivedDraftsFormat.clearConfirmMessage(count: 1) == "Le brouillon archivé de ce topic sera supprimé.")
        #expect(ArchivedDraftsFormat.clearConfirmMessage(count: 3) == "Les 3 brouillons archivés de ce topic seront supprimés.")
    }
}
