import Foundation
import HFRClient
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// "Editer" and "Supprimer" from the message menu (LOT-088), on the real toolbars and HFR's captured answers.
@MainActor
struct MessageWriteModelTests {
    private static let own = 9_910_000_006
    private static let first = 9_910_000_001
    private static let other = 9_910_000_002
    private static let ownPage = "R63a-public-own-topic-first-page.html"

    private struct Fixture {
        let reader: TopicReaderModel
        let writes: MessageWriteModel
        let poster: ScriptedPoster
        let pages: FakeTopicPages
    }

    /// A reader on the real own-topic page, with the handlers the view installs.
    private func fixture(poster: ScriptedPoster, onPage number: Int = 1) async throws -> Fixture {
        var captured = try LiveTopicPageSourceTests.readerPage(of: Self.ownPage)
        captured.currentPage = number
        let page = captured
        let pages = FakeTopicPages { _ in page }
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(try #require(page.topicID)), page: number), source: pages)
        let writes = MessageWriteModel(reader: reader, services: ComposerFixture.services(poster: poster))
        reader.install(MessageActionRegistry(writes.handlers))
        await reader.onAppear()
        return Fixture(reader: reader, writes: writes, poster: poster, pages: pages)
    }

    private func menu(_ fixture: Fixture, post: Int) throws -> MessageMenu? {
        fixture.reader.requestMenu(post: post, source: .message, token: try #require(fixture.reader.document?.token))
        defer { fixture.reader.dismissMenu() }
        return fixture.reader.presentedMenu
    }

    private func target(_ fixture: Fixture, post: Int = own) throws -> EditTarget {
        let page = try #require(fixture.reader.page)
        let message = try #require(page.messages.first { $0.numreponse == post })
        return try #require(EditTarget(link: message.actions.editURL, post: post, topic: page.topicID))
    }

    // MARK: - Menu

    @Test func theMenuOffersEditOnOwnPostsAndDeleteExceptOnTheFirstPost() async throws {
        let fixture = try await fixture(poster: ScriptedPoster([]))
        #expect(try menu(fixture, post: Self.own)?.entries == [.edit, .delete])
        #expect(try menu(fixture, post: Self.first)?.entries == [.edit])
        #expect(try menu(fixture, post: Self.other) == nil)
    }

    /// Off page 1 the first block is not the topic's first post (legacy hid it there too: LOT-087, difference 4).
    @Test func deleteIsOfferedOnTheFirstBlockOfALaterPage() async throws {
        let fixture = try await fixture(poster: ScriptedPoster([]), onPage: 2)
        #expect(try menu(fixture, post: Self.first)?.entries == [.edit, .delete])
    }

    @Test func aTopicLessPageOffersNeither() async throws {
        let captured = try LiveTopicPageSourceTests.readerPage(of: Self.ownPage)
        let context = MessageMenuContext(
            numreponse: Self.own, author: "x", actions: try #require(captured.messages.first { $0.numreponse == Self.own }).actions
        )
        var page = captured
        page.topicID = nil
        let bare = page
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic)), source: FakeTopicPages { _ in bare })
        await reader.onAppear()
        let writes = MessageWriteModel(reader: reader, services: ComposerFixture.services(poster: ScriptedPoster([])))
        #expect(MessageActionRegistry(writes.handlers).entries(for: context, source: .message).isEmpty)
    }

    // MARK: - Edit

    @Test func editReadsTheFormOnceThenOpensTheComposerOnIt() async throws {
        let poster = ScriptedPoster([])
        poster.scriptPrefill([.success(try EditCapture.prefill(EditCapture.laterPostForm))])
        let fixture = try await fixture(poster: poster)
        let menu = try #require(try menu(fixture, post: Self.own))
        fixture.reader.presentedMenu = menu
        await fixture.reader.perform(.edit, in: menu)
        let composer = try #require(fixture.writes.editor)
        #expect(poster.prefillRequests.map(\.post) == [Self.own])
        #expect(composer.isEdit)
        #expect(fixture.writes.progress == nil)
    }

    @Test func aFailedReadOpensNothingAndOffersToReadAgain() async throws {
        let poster = ScriptedPoster([])
        poster.scriptPrefill([
            .failure(.formUnavailable(message: "Message introuvable")), .success(try EditCapture.prefill(EditCapture.laterPostForm))
        ])
        let fixture = try await fixture(poster: poster)
        let target = try target(fixture)
        await fixture.writes.openEditor(target)
        #expect(fixture.writes.editor == nil)
        let failure = try #require(fixture.writes.failure)
        #expect(failure.title == "Edition impossible")
        #expect(failure.message == "Message introuvable")
        #expect(failure.retry == target)
        await fixture.writes.openEditor(target)
        #expect(fixture.writes.editor != nil)
    }

    /// W31: HFR's sentence, and the same page reloaded at the message, without the separator a followed anchor draws.
    @Test func aConfirmedEditShowsHFRsSentenceAndTheMessage() async throws {
        let fixture = try await fixture(poster: ScriptedPoster([]))
        let result = try EditCapture.result(EditCapture.edited, .edit, post: Self.own)
        await fixture.writes.editorDidClose(.sent(result), post: Self.own)
        #expect(fixture.reader.replyConfirmation == "Votre message a été édité avec succès !")
        #expect(fixture.pages.requests.count == 2)
        #expect(fixture.pages.requests.last?.page == 1)
        #expect(fixture.reader.document?.anchor == Self.own)
        #expect(fixture.reader.document?.html.contains("separator1") == false)
    }

    /// After an unconfirmed edit the user sees the message as the forum holds it, and no success.
    @Test func checkingAnUnconfirmedEditReloadsTheMessageWithoutSuccess() async throws {
        let fixture = try await fixture(poster: ScriptedPoster([]))
        await fixture.writes.editorDidClose(.checkTopic, post: Self.own)
        #expect(fixture.reader.replyConfirmation == nil)
        #expect(fixture.pages.requests.count == 2)
        #expect(fixture.reader.document?.anchor == Self.own)
    }

    @Test(arguments: [ReplyComposerModel.CloseReason.keptDraft, .discardedDraft, .closedWithoutSaving])
    func closingWithoutSendingChangesNothing(_ reason: ReplyComposerModel.CloseReason) async throws {
        let fixture = try await fixture(poster: ScriptedPoster([]))
        await fixture.writes.editorDidClose(reason, post: Self.own)
        #expect(fixture.pages.requests.count == 1)
        #expect(fixture.reader.replyConfirmation == nil)
    }

    // MARK: - Delete

    /// The menu entry only asks: nothing leaves before "Oui".
    @Test func deleteAsksFirstAndSendsNothing() async throws {
        let poster = ScriptedPoster([])
        let fixture = try await fixture(poster: poster)
        let menu = try #require(try menu(fixture, post: Self.own))
        fixture.reader.presentedMenu = menu
        await fixture.reader.perform(.delete, in: menu)
        #expect(fixture.writes.pendingDelete?.post == Self.own)
        #expect(poster.calls.isEmpty)
        #expect(poster.prefillRequests.isEmpty)
    }

    /// W32: HFR's sentence and the page reloaded where the user was.
    @Test func aConfirmedDeleteShowsHFRsSentenceAndReloadsThePage() async throws {
        let poster = ScriptedPoster([.success(try EditCapture.result(EditCapture.deleted, .delete, post: Self.own))])
        let fixture = try await fixture(poster: poster)
        let target = try target(fixture)
        fixture.writes.askDelete(target)
        await fixture.writes.confirmDelete(target)
        #expect(fixture.writes.pendingDelete == nil)
        #expect(poster.calls.map(\.isDelete) == [true])
        #expect(poster.calls.first?.post == Self.own)
        #expect(fixture.reader.replyConfirmation == "Message effacé avec succès !")
        #expect(fixture.writes.failure == nil)
        #expect(fixture.pages.requests.count == 2)
        #expect(fixture.reader.document?.keepsScrollPosition == true)
    }

    /// Never reported as a success, never sent again; the page is reloaded so the user sees what happened.
    @Test func anUnconfirmedDeleteIsNotASuccessAndIsNotResent() async throws {
        let poster = ScriptedPoster([.failure(.unconfirmed(.transport(.timedOut)))])
        let fixture = try await fixture(poster: poster)
        await fixture.writes.confirmDelete(try target(fixture))
        #expect(fixture.reader.replyConfirmation == nil)
        let failure = try #require(fixture.writes.failure)
        #expect(failure.message.contains("peut-être été supprimé"))
        #expect(failure.retry == nil)
        #expect(poster.calls.count == 1)
        #expect(fixture.pages.requests.count == 2)
    }

    /// A refused delete says so and leaves the page alone: nothing changed.
    @Test(arguments: [
        (PostingError.rejected(message: "Refusé par le forum"), "Refusé par le forum"),
        (.wholeTopicDeletionNotConfirmed, "Ce message ouvre le sujet : le supprimer emporterait tout le sujet. Rien n’a été supprimé."),
        (.deleteNotOffered, "Le forum ne propose pas de supprimer ce message. Rien n’a été supprimé.")
    ])
    func aRefusedDeleteSaysWhyAndReloadsNothing(error: PostingError, message: String) async throws {
        let poster = ScriptedPoster([.failure(error)])
        let fixture = try await fixture(poster: poster)
        await fixture.writes.confirmDelete(try target(fixture))
        #expect(fixture.reader.replyConfirmation == nil)
        #expect(fixture.writes.failure?.title == "Suppression impossible")
        #expect(fixture.writes.failure?.message == message)
        #expect(fixture.pages.requests.count == 1)
    }
}
