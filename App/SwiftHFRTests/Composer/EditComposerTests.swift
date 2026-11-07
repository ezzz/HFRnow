import Foundation
import HFRClient
import HFRModels
import HFRParsing
import HFRStorage
@testable import SwiftHFR
import Testing

/// What LOT-088 reads from the real captures: the edit link of the toolbar, the prefill of the edit form, HFR's answers.
enum EditCapture {
    /// The captured page `name` as text.
    static func html(_ name: String) throws -> String {
        try #require(String(data: try LiveTopicPageSourceTests.capture(name), encoding: .utf8))
    }

    /// The prefill of a captured edit form.
    static func prefill(_ name: String) throws -> EditPrefill {
        EditPrefill(form: try HopFormParser.parse(try html(name), pageURL: url("https://forum.hardware.fr/message.php")))
    }

    /// HFR's captured answer as `PostingFlow` would report it.
    static func result(_ name: String, _ action: PostingAction, post: Int) throws -> PostingResult {
        let requestURL = url("https://forum.hardware.fr/bdd.php?config=hfr.inc")
        let answer = try HopResponseParser.classify(html: try html(name), context: .write, requestURL: requestURL)
        return PostingResult(
            action: action, message: try #require(answer.message), refreshURL: try #require(answer.refreshURL),
            refreshAnchor: answer.refreshAnchor, postNumber: post
        )
    }

    static let laterPostForm = "R62a-public-edit-form-later-post.html"
    static let firstPostForm = "R63b-public-edit-form-first-post.html"
    static let privateFirstPostForm = "R43a-mp-edit-form-first-post.html"
    static let edited = "W31-public-edit-success.html"
    static let firstPostEdited = "W34-public-first-post-edit-success.html"
    static let deleted = "W32-public-delete-post-success.html"
}

/// `EditTarget` and `EditPrefill` on the captures.
@MainActor
struct EditPrefillTests {
    private static let topic = TopicID(category: .forum(6), topic: 9_900_001)
    private static let link = url(
        "https://forum.hardware.fr/message.php?config=hfr.inc&cat=6&post=9900001&numreponse=9910000006&page=1&p=1&subcat=173#formulaire"
    )

    /// A later post: its text, no title, no select (`R62a`: both are hidden fields sent back as served).
    @Test func aLaterPostOpensOnItsTextAlone() throws {
        let prefill = try EditCapture.prefill(EditCapture.laterPostForm)
        #expect(!prefill.text.isEmpty)
        #expect(prefill.subject == nil)
        #expect(prefill.subcategories == nil)
    }

    /// A public first post: its title, and the sub-category HFR marks selected, the others offered, "Aucune" first (`R63b`).
    @Test func aPublicFirstPostOpensOnItsTitleAndSubcategory() throws {
        let prefill = try EditCapture.prefill(EditCapture.firstPostForm)
        #expect(prefill.subject == "Own topic subject")
        let options = try #require(prefill.subcategories)
        #expect(options.preselected == "173")
        #expect(options.subcategories.count == 12)
        #expect(options.subcategories.first?.value == "")
    }

    /// A private first post has a title and no sub-category (`R43a`).
    @Test func aPrivateFirstPostHasATitleAndNoSubcategory() throws {
        let prefill = try EditCapture.prefill(EditCapture.privateFirstPostForm)
        #expect(prefill.subject == "fixture-test-1")
        #expect(prefill.subcategories == nil)
    }

    /// HFR serves the text of a message stored with a leading line break without it (`R130b`): the composer shows what it served.
    @Test func aLeadingLineBreakIsNotInvented() throws {
        let prefill = try EditCapture.prefill("R130b-mp-edit-form-leading-newline.html")
        #expect(!prefill.text.isEmpty)
        #expect(prefill.text.first?.isNewline == false)
    }

    /// The toolbar's edit links of the capture give a target for their own message and topic.
    @Test func theToolbarLinkOfACapturedOwnPostNamesItsMessage() throws {
        let page = try LiveTopicPageSourceTests.readerPage(of: "R63a-public-own-topic-first-page.html")
        let own = page.messages.filter { $0.actions.editURL != nil }
        #expect(own.count == 3)
        for message in own {
            let target = try #require(EditTarget(link: message.actions.editURL, post: message.numreponse, topic: page.topicID))
            #expect(target.draftContext == .edit(topic: Self.topic, post: message.numreponse))
        }
    }

    @Test(arguments: [
        ("https://forum.hardware.fr/message.php?config=hfr.inc&cat=6&post=9900001&numreponse=1", 2, "another message"),
        ("https://forum.hardware.fr/message.php?config=hfr.inc&cat=6&post=1&numreponse=2", 2, "another topic"),
        ("https://forum.hardware.fr/message.php?config=hfr.inc&cat=7&post=9900001&numreponse=2", 2, "another category"),
        ("http://forum.hardware.fr/message.php?config=hfr.inc&cat=6&post=9900001&numreponse=2", 2, "not https"),
        ("https://forum.hardware.fr:8443/message.php?config=hfr.inc&cat=6&post=9900001&numreponse=2", 2, "another port"),
        ("https://other.example/message.php?config=hfr.inc&cat=6&post=9900001&numreponse=2", 2, "another host")
    ])
    func aLinkThatDoesNotNameTheMessageGivesNoTarget(link: String, post: Int, why: String) {
        #expect(EditTarget(link: url(link), post: post, topic: Self.topic) == nil, "\(why)")
    }

    @Test func noLinkOrNoTopicGivesNoTarget() {
        #expect(EditTarget(link: nil, post: 9_910_000_006, topic: Self.topic) == nil)
        #expect(EditTarget(link: Self.link, post: 9_910_000_006, topic: nil) == nil)
        #expect(EditTarget(link: Self.link, post: 9_910_000_006, topic: Self.topic) != nil)
    }
}

/// The composer of an own message, on the prefill of real edit forms.
@MainActor
struct EditComposerTests {
    private static let link = url(
        "https://forum.hardware.fr/message.php?config=hfr.inc&cat=13&post=28563&numreponse=501&page=5&p=1&subcat=0#formulaire"
    )
    private static var target: EditTarget? { EditTarget(link: link, post: 501, topic: readerTopic) }

    private func composer(
        _ form: String, poster: ScriptedPoster, drafts: DraftStore = DraftStore(persistence: InMemoryDraftPersistence())
    ) async throws -> ReplyComposerModel {
        let model = ReplyComposerModel(
            editing: try #require(Self.target), prefill: try EditCapture.prefill(form),
            services: ComposerFixture.services(poster: poster, drafts: drafts), autosaveDelay: .milliseconds(1)
        )
        await model.start()
        return model
    }

    private func stored(_ drafts: DraftStore) async throws -> Draft? {
        await drafts.draft(for: try #require(Self.target).draftContext, account: ComposerFixture.account)
    }

    /// The message's own text is shown and goes out as typed, once, through that message.
    @Test func anEditOpensOnTheServedTextAndSendsTheNewOne() async throws {
        let served = try EditCapture.prefill(EditCapture.laterPostForm).text
        let answer = try EditCapture.result(EditCapture.edited, .edit, post: 501)
        let poster = ScriptedPoster([.success(answer)])
        let model = try await composer(EditCapture.laterPostForm, poster: poster)
        #expect(model.text == served)
        model.update(text: served + " corrigé")
        #expect(model.canSend)
        await model.send()
        #expect(poster.calls == [.init(text: served + " corrigé", formURL: Self.link, post: 501)])
        #expect(model.closeReason == .sent(answer))
    }

    /// A no-op edit is not offered: it would mark the message edited and lose a leading line break HFR does not serve (`R130b`).
    @Test func anUntouchedEditCannotBeSent() async throws {
        let poster = ScriptedPoster([])
        let model = try await composer("R130b-mp-edit-form-leading-newline.html", poster: poster)
        #expect(!model.canSend)
        await model.send()
        #expect(poster.calls.isEmpty)
    }

    /// Prefill round trip: with only the sub-category changed, the text HFR served goes back byte for byte.
    @Test func aSubcategoryChoiceAloneCanBeSentWithTheServedText() async throws {
        let served = try EditCapture.prefill(EditCapture.firstPostForm).text
        let poster = ScriptedPoster([.success(try EditCapture.result(EditCapture.firstPostEdited, .edit, post: 501))])
        let model = try await composer(EditCapture.firstPostForm, poster: poster)
        #expect(!model.canSend)
        model.select(subcategory: "169")
        #expect(model.canSend)
        await model.send()
        #expect(poster.calls.first?.text == served)
        #expect(poster.calls.first?.subcategory == "169")
    }

    @Test func aFirstPostSendsItsTitleAndSubcategory() async throws {
        let answer = try EditCapture.result(EditCapture.firstPostEdited, .edit, post: 501)
        let poster = ScriptedPoster([.success(answer)])
        let model = try await composer(EditCapture.firstPostForm, poster: poster)
        #expect(model.hasSubjectField)
        #expect(model.offersSubcategories)
        #expect(model.subject == "Own topic subject")
        #expect(model.picker.selected == "173")
        model.update(subject: "  Nouveau titre ")
        model.select(subcategory: "")
        await model.send()
        let call = try #require(poster.calls.first)
        #expect(call.subject == "Nouveau titre")
        #expect(call.subcategory == "")
    }

    /// A private first post has no select: the title alone is sent.
    @Test func aPrivateFirstPostSendsItsTitleAlone() async throws {
        let answer = try EditCapture.result(EditCapture.firstPostEdited, .edit, post: 501)
        let poster = ScriptedPoster([.success(answer)])
        let model = try await composer(EditCapture.privateFirstPostForm, poster: poster)
        #expect(!model.offersSubcategories)
        model.update(subject: "Nouveau titre")
        await model.send()
        #expect(poster.calls.first?.subject == "Nouveau titre")
        #expect(poster.calls.first?.subcategory == nil)
    }

    @Test func aFirstPostNeedsATitle() async throws {
        let model = try await composer(EditCapture.firstPostForm, poster: ScriptedPoster([]))
        model.update(subject: "   ")
        #expect(!model.canSend)
    }

    /// An unconfirmed edit is never reported as sent nor sent again; the text stays and the message says it may have gone.
    @Test func anUnconfirmedEditIsNotASuccessAndIsNotResent() async throws {
        let poster = ScriptedPoster([.failure(.unconfirmed(.transport(.timedOut)))])
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let model = try await composer(EditCapture.laterPostForm, poster: poster, drafts: drafts)
        model.update(text: "corrigé")
        await model.send()
        #expect(model.closeReason == nil)
        #expect(model.mayHavePosted)
        #expect(model.errorMessage?.contains("peut-être été modifié") == true)
        #expect(model.text == "corrigé")
        #expect(try await stored(drafts)?.text == "corrigé")
        #expect(poster.calls.count == 1)
    }

    @Test func aRefusalShowsHFRsSentenceAndKeepsTheText() async throws {
        let poster = ScriptedPoster([.failure(.rejected(message: "Réponse du forum"))])
        let model = try await composer(EditCapture.laterPostForm, poster: poster)
        model.update(text: "corrigé")
        await model.send()
        #expect(model.errorMessage == "Réponse du forum")
        #expect(!model.mayHavePosted)
        #expect(model.closeReason == nil)
    }

    /// A list that changed since the form was read: the form is read again and the user chooses again.
    @Test func aStaleSubcategoryReadsTheFormAgain() async throws {
        let poster = ScriptedPoster([.failure(.unknownSubcategory)])
        poster.scriptPrefill([.success(try EditCapture.prefill(EditCapture.firstPostForm))])
        let model = try await composer(EditCapture.firstPostForm, poster: poster)
        model.select(subcategory: "169")
        await model.send()
        #expect(poster.prefillRequests.count == 1)
        #expect(model.errorMessage?.contains("sous-catégorie") == true)
        #expect(model.picker.selected == "173")
        #expect(poster.calls.count == 1)
    }

    /// That second read fails: the warning talks about the edit, never about a topic to send, and "Réessayer" reads the form again.
    @Test func aFailedRereadOfTheEditFormWarnsAboutTheEdit() async throws {
        let poster = ScriptedPoster([.failure(.unknownSubcategory)])
        poster.scriptPrefill([.failure(.notLoggedIn), .success(try EditCapture.prefill(EditCapture.firstPostForm))])
        let model = try await composer(EditCapture.firstPostForm, poster: poster)
        model.select(subcategory: "169")
        await model.send()
        #expect(model.picker.warning == ComposerMessages.editUnavailable(.notLoggedIn))
        #expect(model.picker.warning?.contains("sujet") == false)
        await model.retrySubcategories()
        #expect(model.picker.warning == nil)
        #expect(model.picker.selected == "173")
        #expect(poster.calls.count == 1)
    }

    /// Nothing changed: closing asks nothing and stores nothing.
    @Test func closingAnUntouchedEditLeavesNoDraft() async throws {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let model = try await composer(EditCapture.laterPostForm, poster: ScriptedPoster([]), drafts: drafts)
        #expect(!model.closeNeedsChoice)
        await model.requestClose()
        #expect(model.closeReason == .discardedDraft)
        #expect(try await stored(drafts) == nil)
    }

    /// The draft of an edit is that message's: it comes back at the next edit, over what the form serves, and never touches the
    /// topic's reply draft.
    @Test func aChangedEditIsKeptPerMessage() async throws {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let model = try await composer(EditCapture.laterPostForm, poster: ScriptedPoster([]), drafts: drafts)
        model.update(text: "corrigé")
        #expect(model.closeNeedsChoice)
        await model.keepDraftAndClose()
        #expect(model.closeReason == .keptDraft)
        #expect(try await stored(drafts)?.text == "corrigé")
        #expect(await ComposerFixture.storedText(drafts) == nil)
        let reopened = try await composer(EditCapture.laterPostForm, poster: ScriptedPoster([]), drafts: drafts)
        #expect(reopened.text == "corrigé")
    }

    /// Typing back to what the form served removes the draft: the next opening shows the message as HFR holds it.
    @Test func anEditBackToTheServedTextDropsTheDraft() async throws {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let served = try EditCapture.prefill(EditCapture.laterPostForm).text
        let model = try await composer(EditCapture.laterPostForm, poster: ScriptedPoster([]), drafts: drafts)
        model.update(text: "corrigé")
        await model.waitForAutosave()
        #expect(try await stored(drafts)?.text == "corrigé")
        model.update(text: served)
        await model.waitForAutosave()
        #expect(try await stored(drafts) == nil)
    }

    @Test func aConfirmedEditRemovesItsDraft() async throws {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let poster = ScriptedPoster([.success(try EditCapture.result(EditCapture.edited, .edit, post: 501))])
        let model = try await composer(EditCapture.laterPostForm, poster: poster, drafts: drafts)
        model.update(text: "corrigé")
        await model.send()
        #expect(try await stored(drafts) == nil)
    }

    /// Each message names the edit, never a reply.
    @Test func theMessagesTalkAboutTheEdit() {
        #expect(ComposerMessages.message(for: .formUnavailable(message: nil), edit: true).contains("modifier ce message"))
        #expect(ComposerMessages.message(for: .sessionChanged, edit: true).contains("la modification"))
        #expect(ComposerMessages.message(for: .unconfirmed(.transport(.timedOut)), edit: true).contains("Vérifiez le sujet"))
        #expect(!ComposerMessages.message(for: .subjectNotEditable, edit: true).contains("réponse"))
        #expect(ComposerMessages.message(for: .unknownSubcategory, edit: true).contains("sous-catégorie"))
    }
}
