import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// LOT-101: the archived drafts of a topic and their picker, as legacy `ReplyDraftPickerSheet` (`AnswerView.swift:693-760` @ 87fe0d1c).
@MainActor
struct ArchivedDraftsTests {
    private func opened(
        _ drafts: DraftStore = DraftStore(persistence: InMemoryDraftPersistence()), poster: ScriptedPoster = ScriptedPoster([])
    ) async -> ReplyComposerModel {
        let composer = ComposerFixture.model(poster: poster, drafts: drafts)
        await composer.start()
        return composer
    }

    private func archived(_ drafts: DraftStore, account: String = ComposerFixture.account) async -> [String] {
        await drafts.archivedReplies(topic: replyTarget.topic, account: account).map(\.text)
    }

    @Test func theTopicsArchiveIsReadWhenTheSheetOpens() async throws {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        try await drafts.archiveReply("mine", topic: replyTarget.topic, source: .quote, account: ComposerFixture.account)
        try await drafts.archiveReply("theirs", topic: replyTarget.topic, source: .quickReply, account: "user2")
        let other = TopicID(category: .forum(13), topic: 6510)
        try await drafts.archiveReply("elsewhere", topic: other, source: .quickReply, account: ComposerFixture.account)
        let composer = await opened(drafts)
        #expect(composer.archivedDrafts.map(\.text) == ["mine"])
    }

    @Test func setAsideEmptiesTheEditorAndRemovesTheActiveDraft() async {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let composer = await opened(drafts)
        composer.update(text: "à garder")
        await composer.flushDraft()
        #expect(await ComposerFixture.storedText(drafts) == "à garder")
        await composer.archiveAndClear()
        #expect(composer.text.isEmpty)
        #expect(await archived(drafts) == ["à garder"])
        #expect(await ComposerFixture.storedText(drafts) == nil)
        #expect(composer.archivedDrafts.map(\.text) == ["à garder"])
        #expect(composer.canEdit)
    }

    @Test func blankTextCannotBeSetAside() async {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let composer = await opened(drafts)
        #expect(!composer.canArchiveCurrent)
        composer.update(text: " \n")
        #expect(!composer.canArchiveCurrent)
        await composer.archiveAndClear()
        #expect(await archived(drafts).isEmpty)
    }

    @Test func aQuoteOpensTheSheetLabelledAsACitation() async throws {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let composer = ReplyComposerModel(
            composing: .reply(replyTarget), services: ComposerFixture.services(poster: ScriptedPoster([]), drafts: drafts),
            autosaveDelay: .seconds(60), quote: ReplyQuote(text: "[quotemsg=1,1,1]x[/quotemsg]")
        )
        await composer.start()
        await composer.archiveAndClear()
        let list = await drafts.archivedReplies(topic: replyTarget.topic, account: ComposerFixture.account)
        #expect(list.map(\.source) == [.quote])
    }

    @Test func pickingWithAnEmptyEditorKeepsItInTheArchive() async throws {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        try await drafts.archiveReply("ancien", topic: replyTarget.topic, source: .quote, account: ComposerFixture.account)
        let composer = await opened(drafts)
        let pick = try #require(composer.archivedDrafts.first)
        await composer.use(pick)
        #expect(composer.text == "ancien")
        #expect(await archived(drafts) == ["ancien"])
        #expect(composer.draftSource == .quote)
        #expect(await ComposerFixture.storedText(drafts) == "ancien")
    }

    @Test func pickingSetsADifferentCurrentTextAsideFirstThenTheDraftComesToTheTop() async throws {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        try await drafts.archiveReply("ancien", topic: replyTarget.topic, source: .quote, account: ComposerFixture.account)
        let composer = await opened(drafts)
        composer.update(text: "en cours")
        let pick = try #require(composer.archivedDrafts.first)
        await composer.use(pick)
        #expect(composer.text == "ancien")
        #expect(await archived(drafts) == ["ancien", "en cours"])
        #expect(await ComposerFixture.storedText(drafts) == "ancien")
    }

    /// The swap is one step of "Annuler" (#749, legacy `archiveAndClearCurrentDraft` pushes the text it clears,
    /// `AnswerView.swift:734-735` @ 87fe0d1c): undo brings the whole text back, not the keystroke before it.
    @Test func undoAfterSetAsideBringsTheWholeTextBack() async {
        let composer = await opened()
        composer.update(text: "a")
        composer.update(text: "ab")
        composer.update(text: "abc")
        await composer.archiveAndClear()
        #expect(composer.text.isEmpty)
        #expect(composer.canUndo)
        composer.undo()
        #expect(composer.text == "abc")
        composer.redo()
        #expect(composer.text.isEmpty)
    }

    /// Same for a pick (legacy `useDraft` pushes the text it replaces, `AnswerView.swift:711-712` @ 87fe0d1c).
    @Test func undoAfterPickingBringsTheReplacedTextBack() async throws {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        try await drafts.archiveReply("ancien", topic: replyTarget.topic, source: .quote, account: ComposerFixture.account)
        let composer = await opened(drafts)
        composer.update(text: "e")
        composer.update(text: "en cours")
        await composer.use(try #require(composer.archivedDrafts.first))
        #expect(composer.text == "ancien")
        composer.undo()
        #expect(composer.text == "en cours")
    }

    @Test func pickingTheSameTextArchivesNothingNew() async throws {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        try await drafts.archiveReply("même", topic: replyTarget.topic, source: .quickReply, account: ComposerFixture.account)
        let composer = await opened(drafts)
        composer.update(text: "même  ")
        await composer.use(try #require(composer.archivedDrafts.first))
        #expect(await archived(drafts) == ["même"])
    }

    @Test func theArchiveKeepsThreeAndTheFourthSetAsideDropsTheOldest() async {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let composer = await opened(drafts)
        for text in ["un", "deux", "trois", "quatre"] {
            composer.update(text: text)
            await composer.archiveAndClear()
        }
        #expect(composer.archivedDrafts.map(\.text) == ["quatre", "trois", "deux"])
    }

    @Test func deletingOneAndEmptyingTheTopic() async throws {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        for text in ["a", "b"] {
            try await drafts.archiveReply(text, topic: replyTarget.topic, source: .quickReply, account: ComposerFixture.account)
        }
        try await drafts.archiveReply("autre compte", topic: replyTarget.topic, source: .quickReply, account: "user2")
        let composer = await opened(drafts)
        await composer.discardArchived(try #require(composer.archivedDrafts.first))
        #expect(composer.archivedDrafts.map(\.text) == ["a"])
        await composer.discardAllArchived()
        #expect(composer.archivedDrafts.isEmpty)
        #expect(await archived(drafts, account: "user2") == ["autre compte"])
    }

    @Test func aConfirmedReplyRemovesThePickedDraftButNotTheOthers() async throws {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        try await drafts.archiveReply("autre", topic: replyTarget.topic, source: .quickReply, account: ComposerFixture.account)
        try await drafts.archiveReply("choisi", topic: replyTarget.topic, source: .quickReply, account: ComposerFixture.account)
        let composer = await opened(drafts, poster: ScriptedPoster([.success(replyConfirmed)]))
        await composer.use(try #require(composer.archivedDrafts.first))
        await composer.send()
        #expect(composer.closeReason == .sent(replyConfirmed))
        #expect(await archived(drafts) == ["autre"])
    }

    @Test func aFailedSendKeepsThePickedDraftInTheArchive() async throws {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        try await drafts.archiveReply("choisi", topic: replyTarget.topic, source: .quickReply, account: ComposerFixture.account)
        let composer = await opened(drafts, poster: ScriptedPoster([.failure(.network(.offline))]))
        await composer.use(try #require(composer.archivedDrafts.first))
        await composer.send()
        #expect(composer.closeReason == nil)
        #expect(await archived(drafts) == ["choisi"])
    }

    @Test func nothingIsChangedWhenTheArchiveCannotBeWritten() async throws {
        let persistence = CountingDraftPersistence()
        let drafts = DraftStore(persistence: persistence)
        let composer = await opened(drafts)
        composer.update(text: "précieux")
        await composer.flushDraft()
        persistence.failSaves(true)
        await composer.archiveAndClear()
        #expect(composer.text == "précieux")
        #expect(composer.draftWarning != nil)
        #expect(composer.canEdit)
    }

    /// The pending autosave is settled first, so the only write is the archive's: no active draft is stored, before or after
    /// the autosave's delay. (A late autosave would also read an empty text, so this pins the outcome, not the ordering.)
    @Test func aPendingAutosaveLeavesNoActiveDraftAfterASetAside() async {
        let persistence = CountingDraftPersistence()
        let drafts = DraftStore(persistence: persistence)
        let composer = ComposerFixture.model(poster: ScriptedPoster([]), drafts: drafts, autosaveDelay: .milliseconds(50))
        await composer.start()
        composer.update(text: "en attente")
        await composer.archiveAndClear()
        await composer.waitForAutosave()
        try? await Task.sleep(for: .milliseconds(120))
        #expect(persistence.saves == 1)
        #expect(await ComposerFixture.storedText(drafts) == nil)
        #expect(await archived(drafts) == ["en attente"])
        #expect(composer.canEdit)
    }

    @Test func nothingIsDeletedFromTheArchiveWhileAMoveRuns() async throws {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        try await drafts.archiveReply("a", topic: replyTarget.topic, source: .quickReply, account: ComposerFixture.account)
        let composer = await opened(drafts)
        composer.isMovingDrafts = true
        await composer.discardAllArchived()
        await composer.discardArchived(try #require(composer.archivedDrafts.first))
        composer.isMovingDrafts = false
        #expect(await archived(drafts) == ["a"])
        #expect(composer.canEdit)
    }

    @Test func otherComposersHaveNoArchive() async {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let composer = ReplyComposerModel(
            composing: .newPrivateMessage(newMessageTarget),
            services: ComposerFixture.services(poster: ScriptedPoster([]), drafts: drafts), autosaveDelay: .seconds(60)
        )
        await composer.start()
        composer.update(text: "mp")
        #expect(!composer.offersArchivedDrafts)
        #expect(!composer.canArchiveCurrent)
        await composer.archiveAndClear()
        #expect(composer.text == "mp")
    }
}

/// What the picker prints (legacy `formattedDate`, `previewText`).
struct ArchivedDraftsFormatTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        return calendar
    }()
    private let locale = Locale(identifier: "fr_FR")
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 18, minute: 30)) ?? .now }

    private func label(daysAgo: Int, hour: Int = 14, minute: Int = 5) -> String {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        return ArchivedDraftsFormat.dateLabel(of: date, now: now, calendar: calendar, locale: locale)
    }

    @Test func todayAndYesterdayNameTheDay() {
        #expect(label(daysAgo: 0) == "Aujourd’hui 14:05")
        #expect(label(daysAgo: 1) == "Hier 14:05")
    }

    @Test func olderDraftsGetTheShortDateAndTime() {
        let older = label(daysAgo: 5)
        #expect(older.contains("14:05"))
        #expect(!older.contains("Hier"))
        #expect(!older.contains("Aujourd’hui"))
    }

    @Test func thePreviewIsOneLine() {
        #expect(ArchivedDraftsFormat.preview(of: "a\r\n\r\nb\rc\n") == "a b c")
        #expect(ArchivedDraftsFormat.preview(of: " \n ") == "Brouillon vide")
    }

    @Test func sourcesHaveLegacyTitles() {
        #expect(ArchivedDraftsFormat.title(of: .quickReply) == "Réponse rapide")
        #expect(ArchivedDraftsFormat.title(of: .quote) == "Citation")
    }
}
