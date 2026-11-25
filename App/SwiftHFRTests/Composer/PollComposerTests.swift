import Foundation
import HFRClient
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// The poll of the composer (LOT-100): offered on a new topic and on a public first post's edit, sent only through a form that
/// adds one (`R63b`, `W41`), never sent incomplete.
@MainActor
struct PollComposerTests {
    private static let link = url(
        "https://forum.hardware.fr/message.php?config=hfr.inc&cat=13&post=28563&numreponse=501&page=5&p=1&subcat=0#formulaire"
    )
    private static let privateLink = url(
        "https://forum.hardware.fr/message.php?config=hfr.inc&cat=prive&post=3207033&numreponse=501&page=1&p=1&subcat=0#formulaire"
    )
    private static let poll = PollDraft(question: "fixture-test poll", answers: ["A", "B"])

    private func editComposer(
        _ form: String, poster: ScriptedPoster, link: URL = link, topic: TopicID = readerTopic
    ) async throws -> ReplyComposerModel {
        let model = ReplyComposerModel(
            editing: try #require(EditTarget(link: link, post: 501, topic: topic)), prefill: try EditCapture.prefill(form),
            services: ComposerFixture.services(poster: poster), autosaveDelay: .seconds(60)
        )
        await model.start()
        return model
    }

    private func newTopicComposer(_ poster: ScriptedPoster) async -> ReplyComposerModel {
        let model = ReplyComposerModel(
            composing: .newTopic(newTopicTarget), services: ComposerFixture.services(poster: poster), autosaveDelay: .seconds(60)
        )
        await model.start()
        await model.loadSubcategories()
        return model
    }

    /// `R63b`: the poll is offered; with it, the served text alone can be sent, and the poll goes with the edit.
    @Test func aPublicFirstPostAddsAPollWithItsEdit() async throws {
        let answer = try EditCapture.result("W41-public-first-post-edit-add-poll-success.html", .edit, post: 501)
        let poster = ScriptedPoster([.success(answer)])
        let model = try await editComposer(EditCapture.firstPostForm, poster: poster)
        #expect(model.showsPoll)
        #expect(model.poll.availability == .offered)
        #expect(!model.canSend)
        model.set(poll: Self.poll)
        #expect(model.poll.draft == Self.poll)
        #expect(model.canSend)
        await model.send()
        let call = try #require(poster.calls.first)
        #expect(call.poll == Self.poll)
        #expect(call.text == model.prefill?.text)
        #expect(model.closeReason == .sent(answer))
    }

    /// "Retirer": the edit goes out without a poll, and an untouched edit is again not sendable.
    @Test func aRemovedPollIsNotSent() async throws {
        let poster = ScriptedPoster([.success(try EditCapture.result(EditCapture.firstPostEdited, .edit, post: 501))])
        let model = try await editComposer(EditCapture.firstPostForm, poster: poster)
        model.set(poll: Self.poll)
        model.removePoll()
        #expect(model.poll.draft == nil)
        #expect(!model.canSend)
        model.update(subject: "Nouveau titre")
        await model.send()
        #expect(poster.calls.first?.poll == nil)
    }

    /// An incomplete poll blocks Send and says why (legacy `AnswerView.swift:434`).
    @Test func anIncompletePollBlocksSend() async throws {
        let poster = ScriptedPoster([])
        let model = try await editComposer(EditCapture.firstPostForm, poster: poster)
        model.update(text: "corrigé")
        model.set(poll: PollDraft(question: "Q", answers: ["A", " "]))
        #expect(model.poll.draft != nil)
        #expect(!model.canSend)
        await model.send()
        #expect(poster.calls.isEmpty)
        #expect(ComposerMessages.poll(.tooFewAnswers) == "Saisis au moins deux réponses.")
    }

    /// A later post (`R62a`) has no poll row; a private thread's first post (`R43a`) neither.
    @Test func noPollOnALaterPostNorOnAPrivateThread() async throws {
        let later = try await editComposer(EditCapture.laterPostForm, poster: ScriptedPoster([]))
        #expect(!later.showsPoll)
        let privateTopic = TopicID(category: .privateMessages, topic: 3_207_033)
        let first = try await editComposer(
            EditCapture.privateFirstPostForm, poster: ScriptedPoster([]), link: Self.privateLink, topic: privateTopic
        )
        #expect(first.hasSubjectField)
        #expect(!first.showsPoll)
    }

    /// A public first post whose form has no poll box (`R43a`'s form standing in: no `have_sondage`): shown, off, nothing set.
    @Test func aFirstPostFormWithoutThePollBlockKeepsTheButtonOff() async throws {
        let model = try await editComposer(EditCapture.privateFirstPostForm, poster: ScriptedPoster([]))
        #expect(model.showsPoll)
        #expect(model.poll.availability == .notOffered)
        model.set(poll: Self.poll)
        #expect(model.poll.draft == nil)
    }

    /// A new topic: the row is shown, off, since the form has no poll box (`R45a`); legacy says to edit the first post.
    @Test func aNewTopicShowsThePollOff() async {
        let poster = ScriptedPoster([])
        poster.scriptOptions([.success(newTopicOptions)])
        let model = await newTopicComposer(poster)
        #expect(model.showsPoll)
        #expect(model.poll.availability == .notOffered)
        model.set(poll: Self.poll)
        #expect(model.poll.draft == nil)
    }

    /// The form could not be read: the poll is off, and the sub-category row's retry reads it again.
    @Test func aFailedReadTurnsThePollOffUntilRetried() async {
        let poster = ScriptedPoster([])
        poster.scriptOptions([.failure(.network(.timedOut)), .success(newTopicOptions)])
        let model = await newTopicComposer(poster)
        #expect(model.poll.availability == .failed)
        await model.retrySubcategories()
        #expect(model.poll.availability == .notOffered)
    }

    /// The form no longer adds a poll at send: nothing was sent, the poll stays to remove, and Send waits for that.
    @Test func aFormThatNoLongerOffersThePollStopsSend() async throws {
        let poster = ScriptedPoster([.failure(.pollNotOffered)])
        let model = try await editComposer(EditCapture.firstPostForm, poster: poster)
        model.set(poll: Self.poll)
        await model.send()
        #expect(model.errorMessage == ComposerMessages.message(for: .pollNotOffered, edit: true))
        #expect(model.errorMessage?.contains("ne permet plus de créer un sondage") == true)
        #expect(!model.mayHavePosted)
        #expect(model.poll.availability == .notOffered)
        #expect(model.poll.draft == Self.poll)
        #expect(!model.canSend)
        model.removePoll()
        #expect(!model.canSend)
        model.update(text: "corrigé")
        #expect(model.canSend)
    }

    /// The form fetched at send lacks a poll field: the message says to remove the poll, not to retry as is.
    @Test func aFormThatCannotTakeThePollSaysToRemoveIt() async throws {
        let poster = ScriptedPoster([.failure(.unsupportedForm(reason: "poll field max_votes"))])
        let model = try await editComposer(EditCapture.firstPostForm, poster: poster)
        model.set(poll: Self.poll)
        await model.send()
        #expect(model.errorMessage == ComposerMessages.pollUnsupportedForm)
        #expect(!model.mayHavePosted)
    }

    /// An invalid poll the engine refused names its problem and says nothing was sent.
    @Test func anInvalidPollMessageNamesTheProblem() {
        let message = ComposerMessages.message(for: .invalidPoll(.closingDateNotInFuture), edit: true)
        #expect(message.contains("Choisis une date de clôture future."))
        #expect(message.contains("Rien n’a été envoyé"))
    }
}
