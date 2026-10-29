import Foundation
import HFRClient
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// The reply draft: per topic and account, restored, saved while typing (debounced) and when the app leaves the
/// foreground, kept or discarded on close as the user chooses, never written before it was read.
@MainActor
struct ReplyComposerDraftTests {
    @Test func theTopicDraftOfTheCurrentAccountIsRestored() async throws {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        try await drafts.save("Brouillon de user1", for: replyTarget.draftContext, account: "user1")
        try await drafts.save("Brouillon de user2", for: replyTarget.draftContext, account: "user2")
        let other = TopicID(category: .forum(13), topic: 6510)
        try await drafts.save("Autre sujet", for: .reply(topic: other, page: 1), account: "user1")
        let composer = ComposerFixture.model(poster: ScriptedPoster([]), drafts: drafts)
        #expect(!composer.canEdit)
        await composer.start()
        #expect(composer.text == "Brouillon de user1")
        #expect(composer.canEdit)
    }

    @Test func typingSavesTheDraftOnceAfterAPause() async {
        let persistence = CountingDraftPersistence()
        let drafts = DraftStore(persistence: persistence)
        let composer = ComposerFixture.model(poster: ScriptedPoster([]), drafts: drafts, autosaveDelay: .milliseconds(50))
        await composer.start()
        composer.update(text: "a")
        composer.update(text: "ab")
        composer.update(text: "abc")
        #expect(persistence.saves == 0)
        await composer.waitForAutosave()
        #expect(persistence.saves == 1)
        #expect(await ComposerFixture.storedText(drafts) == "abc")
    }

    @Test func theDraftSurvivesAKillOfTheApp() async throws {
        let directory = URL.temporaryDirectory.appending(path: "LOT-084-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "drafts.json")
        let before = ComposerFixture.model(
            poster: ScriptedPoster([]), drafts: DraftStore(persistence: FileDraftPersistence(fileURL: file)),
            autosaveDelay: .milliseconds(10)
        )
        await before.start()
        before.update(text: "Écrit avant le kill")
        await before.waitForAutosave()
        // A new process: a new store over the same file, a new sheet.
        let after = ComposerFixture.model(
            poster: ScriptedPoster([]), drafts: DraftStore(persistence: FileDraftPersistence(fileURL: file))
        )
        await after.start()
        #expect(after.text == "Écrit avant le kill")
    }

    @Test func goingToTheBackgroundWritesThePendingDraftNow() async {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let composer = ComposerFixture.model(poster: ScriptedPoster([]), drafts: drafts)
        await composer.start()
        composer.update(text: "Avant l’appel")
        await composer.flushDraft()
        #expect(await ComposerFixture.storedText(drafts) == "Avant l’appel")
    }

    @Test func nothingIsWrittenBeforeTheDraftWasRead() async throws {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        try await drafts.save("Ancien brouillon", for: replyTarget.draftContext, account: ComposerFixture.account)
        let composer = ComposerFixture.model(poster: ScriptedPoster([]), drafts: drafts)
        composer.update(text: "")
        await composer.flushDraft()
        await composer.requestClose()
        #expect(composer.closeReason == .keptDraft)
        #expect(await ComposerFixture.storedText(drafts) == "Ancien brouillon")
    }

    @Test func closingWithTextAsksAndKeepsTheDraft() async {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let composer = ComposerFixture.model(poster: ScriptedPoster([]), drafts: drafts)
        await composer.start()
        composer.update(text: "À garder")
        await composer.requestClose()
        #expect(composer.isAskingClose)
        #expect(composer.closeReason == nil)
        await composer.keepDraftAndClose()
        #expect(composer.closeReason == .keptDraft)
        #expect(await ComposerFixture.storedText(drafts) == "À garder")
    }

    @Test func closingWithTextCanDiscardTheDraft() async throws {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        try await drafts.save("Ancien", for: replyTarget.draftContext, account: ComposerFixture.account)
        let composer = ComposerFixture.model(poster: ScriptedPoster([]), drafts: drafts, autosaveDelay: .milliseconds(20))
        await composer.start()
        composer.update(text: "À jeter")
        await composer.requestClose()
        await composer.discardDraftAndClose()
        try await Task.sleep(for: .milliseconds(100))
        #expect(composer.closeReason == .discardedDraft)
        #expect(await ComposerFixture.storedText(drafts) == nil)
    }

    @Test func closingAnEmptiedTextRemovesTheDraftWithoutAsking() async throws {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        try await drafts.save("Ancien", for: replyTarget.draftContext, account: ComposerFixture.account)
        let composer = ComposerFixture.model(poster: ScriptedPoster([]), drafts: drafts)
        await composer.start()
        composer.update(text: "")
        await composer.requestClose()
        #expect(!composer.isAskingClose)
        #expect(composer.closeReason == .discardedDraft)
        #expect(await ComposerFixture.storedText(drafts) == nil)
    }

    @Test func aFailedDraftWriteIsReportedAndTheTextStays() async {
        let persistence = CountingDraftPersistence()
        let composer = ComposerFixture.model(poster: ScriptedPoster([]), drafts: DraftStore(persistence: persistence))
        await composer.start()
        persistence.failSaves(true)
        composer.update(text: "Disque plein")
        await composer.flushDraft()
        #expect(composer.draftWarning != nil)
        #expect(composer.text == "Disque plein")
        persistence.failSaves(false)
        await composer.flushDraft()
        #expect(composer.draftWarning == nil)
    }

    @Test func keepingADraftThatCannotBeWrittenLeavesTheSheetOpen() async {
        let persistence = CountingDraftPersistence()
        let drafts = DraftStore(persistence: persistence)
        let composer = ComposerFixture.model(poster: ScriptedPoster([]), drafts: drafts)
        await composer.start()
        composer.update(text: "À ne pas perdre")
        persistence.failSaves(true)
        await composer.keepDraftAndClose()
        #expect(composer.closeReason == nil)
        #expect(composer.draftWarning != nil)
        #expect(composer.canEdit)
        persistence.failSaves(false)
        await composer.keepDraftAndClose()
        #expect(composer.closeReason == .keptDraft)
        #expect(await ComposerFixture.storedText(drafts) == "À ne pas perdre")
    }

    @Test func checkingTheTopicWithADraftThatCannotBeWrittenLeavesTheSheetOpen() async {
        let persistence = CountingDraftPersistence()
        let poster = ScriptedPoster([.failure(.unconfirmed(.transport(.timedOut)))])
        let composer = ComposerFixture.model(poster: poster, drafts: DraftStore(persistence: persistence))
        await composer.start()
        composer.update(text: "Peut-être postée")
        persistence.failSaves(true)
        await composer.send()
        #expect(poster.calls.count == 1)
        await composer.checkTopic()
        #expect(composer.closeReason == nil)
        #expect(composer.mayHavePosted)
        persistence.failSaves(false)
        await composer.checkTopic()
        #expect(composer.closeReason == .checkTopic)
    }

    @Test func discardingADraftThatCannotBeDeletedLeavesTheSheetOpen() async throws {
        let persistence = CountingDraftPersistence()
        let drafts = DraftStore(persistence: persistence)
        try await drafts.save("Ancien", for: replyTarget.draftContext, account: ComposerFixture.account)
        let composer = ComposerFixture.model(poster: ScriptedPoster([]), drafts: drafts)
        await composer.start()
        persistence.failSaves(true)
        await composer.discardDraftAndClose()
        #expect(composer.closeReason == nil)
        #expect(composer.draftWarning != nil)
        #expect(composer.canEdit)
        persistence.failSaves(false)
        await composer.discardDraftAndClose()
        #expect(composer.closeReason == .discardedDraft)
        #expect(await ComposerFixture.storedText(drafts) == nil)
    }

    @Test func aStoreThatRefusesEveryWriteStillLetsTheSheetClose() async {
        let composer = ComposerFixture.model(poster: ScriptedPoster([]), drafts: DraftStore(persistence: UnreadableDraftPersistence()))
        await composer.start()
        composer.update(text: "Sans brouillon")
        await composer.requestClose()
        #expect(composer.isAskingClose)
        await composer.keepDraftAndClose()
        await composer.discardDraftAndClose()
        // Both choices write and the store refuses: the sheet is still open, and the warning's exit is the way out.
        #expect(composer.closeReason == nil)
        #expect(composer.canCloseWithoutSaving)
        await composer.closeWithoutSaving()
        #expect(composer.closeReason == .closedWithoutSaving)
    }

    @Test func closingWithoutSavingLeavesTheStoredDraftAndWritesNothingAfterwards() async throws {
        let persistence = CountingDraftPersistence()
        let drafts = DraftStore(persistence: persistence)
        try await drafts.save("Ancien", for: replyTarget.draftContext, account: ComposerFixture.account)
        let composer = ComposerFixture.model(poster: ScriptedPoster([]), drafts: drafts, autosaveDelay: .milliseconds(20))
        await composer.start()
        #expect(!composer.canCloseWithoutSaving)
        persistence.failSaves(true)
        composer.update(text: "")
        // Cancel on an emptied text deletes the draft without asking; the store refuses, so the sheet stays open.
        await composer.requestClose()
        #expect(!composer.isAskingClose)
        #expect(composer.closeReason == nil)
        #expect(composer.canCloseWithoutSaving)
        composer.update(text: "Nouveau")
        await composer.closeWithoutSaving()
        #expect(composer.closeReason == .closedWithoutSaving)
        // The store works again: the autosave scheduled by the last keystroke must not land after the choice.
        persistence.failSaves(false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(await ComposerFixture.storedText(drafts) == "Ancien")
    }

    @Test func aWhitespaceOnlyTextLeavesNoDraft() async throws {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        try await drafts.save("Ancien", for: replyTarget.draftContext, account: ComposerFixture.account)
        let composer = ComposerFixture.model(poster: ScriptedPoster([]), drafts: drafts)
        await composer.start()
        composer.update(text: " \n\t ")
        await composer.flushDraft()
        #expect(await ComposerFixture.storedText(drafts) == nil)
    }

    @Test func anUnreadableDraftFileIsReportedAndTheEditorStillWorks() async {
        let composer = ComposerFixture.model(poster: ScriptedPoster([]), drafts: DraftStore(persistence: UnreadableDraftPersistence()))
        await composer.start()
        #expect(composer.draftWarning != nil)
        #expect(composer.canEdit)
        composer.update(text: "Quand même")
        #expect(composer.canSend)
    }
}
