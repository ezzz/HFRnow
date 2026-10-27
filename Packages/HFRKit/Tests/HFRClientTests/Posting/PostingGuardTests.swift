import Foundation
import HFRModels
import HFRNetwork
import Testing
@testable import HFRClient

/// Guards added after the Fable review of #36: whole-thread deletes fail closed outside private threads, one-line inputs,
/// and an empty stored text on delete. Pages are captures with one attribute or text edited, labelled where used.
@Suite("Posting flow: delete and one-line guards")
struct PostingGuardTests {
    private func expectNoPost(_ outcome: PostingHarness.Outcome, _ error: PostingError) {
        #expect(outcome.error == error)
        #expect(outcome.requests.count == 1)
        #expect(outcome.post == nil)
    }

    /// `R43a` with neither first-post sign: subject hidden and the later-post label.
    private func r43aWithoutSigns(public isPublic: Bool) throws -> Result<HTTPResponse, NetworkError> {
        try PostingHarness.editedForm("R43a") { page in
            var page = page
                .replacing(
                    "<input maxlength=\"70\" accesskey=\"t\" size=\"50\" name=\"sujet\"", with: "<input type=\"hidden\" name=\"sujet\""
                )
                .replacing("Effacer l'intégralité du sujet", with: "Effacer ce message")
            if isPublic { page = Self.publicThread(page) }
            return page
        }
    }

    /// The same page as if the thread were in forum category 13 (public edit forms are not captured).
    private static func publicThread(_ page: String) -> String {
        page.replacing("name=\"cat\" value=\"prive\"", with: "name=\"cat\" value=\"13\"")
            .replacing("name=\"cat\" id=\"catid\" value=\"prive\"", with: "name=\"cat\" id=\"catid\" value=\"13\"")
    }

    private func delete(
        _ page: Result<HTTPResponse, NetworkError>,
        formID: String,
        answer: String? = nil,
        isFirstPost: Bool = false,
        confirming: Bool = false
    ) async throws -> PostingHarness.Outcome {
        await PostingHarness.run(
            formPage: page, formURL: try PostingCapture.pageURL(formID), answer: try answer.map { try PostingCapture.answer($0) }
        ) { flow, form async throws(PostingError) in
            try await flow.delete(with: form, isFirstPost: isFirstPost, confirmingWholeTopic: confirming)
        }
    }

    @Test("Probe (R43a without its signs, as a public topic): a delete needs confirmation, nothing sent")
    func publicFirstPostWithoutSigns() async throws {
        let outcome = try await delete(try r43aWithoutSigns(public: true), formID: "R43a")
        expectNoPost(outcome, .wholeTopicDeletionNotConfirmed)
        let confirmed = try await delete(try r43aWithoutSigns(public: true), formID: "R43a", answer: "W19", confirming: true)
        #expect(confirmed.post != nil)
        #expect(confirmed.error == nil)
    }

    @Test("Probe (R43a without its signs, private): the caller's isFirstPost hint asks for confirmation")
    func firstPostHint() async throws {
        let hinted = try await delete(try r43aWithoutSigns(public: false), formID: "R43a", isFirstPost: true)
        expectNoPost(hinted, .wholeTopicDeletionNotConfirmed)
        // Private thread, no sign and no hint: the form signs are trusted there (R43b is such a later post, W16a).
        let session = ScriptedPostingSession([try r43aWithoutSigns(public: false)])
        let form = try await PostingFlow().loadForm(at: try PostingCapture.pageURL("R43a"), through: session)
        #expect(form.isPrivateThread)
        #expect(!form.requiresWholeTopicConfirmation())
        #expect(form.requiresWholeTopicConfirmation(isFirstPost: true))
    }

    @Test("A later post of a public topic (R43b as category 13) still needs confirmation")
    func publicLaterPost() async throws {
        let page = try PostingHarness.editedForm("R43b") { Self.publicThread($0) }
        let outcome = try await delete(page, formID: "R43b")
        expectNoPost(outcome, .wholeTopicDeletionNotConfirmed)
    }

    @Test("A delete whose stored text is empty is refused locally (HFR refuses an empty content_form, W17a)")
    func emptyStoredText() async throws {
        let page = try PostingHarness.editedForm("R43c") {
            $0.replacing("accesskey=\"c\">fixture-test 3, before", with: "accesskey=\"c\">")
        }
        let outcome = try await delete(page, formID: "R43c")
        expectNoPost(outcome, .emptyInput(.text))
    }

    @Test("A line break in a subject or a recipient is refused", arguments: ["line1\nline2", "line1\r\nline2", "a\rb"])
    func lineBreaks(value: String) async throws {
        let subject = try await PostingHarness.run(form: "R45b") { flow, form async throws(PostingError) in
            try await flow.newPrivateMessage(to: "user1", subject: value, text: "text", with: form)
        }
        expectNoPost(subject, .lineBreak(.subject))
        let recipient = try await PostingHarness.run(form: "R45b") { flow, form async throws(PostingError) in
            try await flow.newPrivateMessage(to: value, subject: "s", text: "text", with: form)
        }
        expectNoPost(recipient, .lineBreak(.recipient))
        let topic = try await PostingHarness.run(form: "R45a") { flow, form async throws(PostingError) in
            try await flow.newTopic(subject: value, text: "text", with: form)
        }
        expectNoPost(topic, .lineBreak(.subject))
    }

    @Test("A subject longer than the form's maxlength (70 on R45a, R43a) is refused; 70 is accepted")
    func subjectMaxLength() async throws {
        let tooLong = try await PostingHarness.run(form: "R45a") { flow, form async throws(PostingError) in
            try await flow.newTopic(subject: String(repeating: "é", count: 71), text: "text", with: form)
        }
        expectNoPost(tooLong, .tooLong(.subject, maximum: 70))
        let edit = try await PostingHarness.run(form: "R43a") { flow, form async throws(PostingError) in
            try await flow.edit("text", subject: String(repeating: "x", count: 71), with: form)
        }
        expectNoPost(edit, .tooLong(.subject, maximum: 70))
        let exact = try await PostingHarness.run(form: "R45a", answer: "W10") { flow, form async throws(PostingError) in
            try await flow.newTopic(subject: String(repeating: "é", count: 70), text: "text", with: form)
        }
        #expect(exact.error == nil)
    }

    @Test(
        "Derived (R47b, R45a, R45b with a checked delete box): a non-delete write never sends delete",
        arguments: ["R47b", "R45a", "R45b"]
    )
    func deleteNeverEchoed(formID: String) async throws {
        let page = try PostingHarness.editedForm(formID) {
            $0.replacing(
                "name=\"emaill\" id=\"emaill\" />",
                with: "name=\"emaill\" id=\"emaill\" /><input type=\"checkbox\" value=\"1\" name=\"delete\" checked=\"checked\" />"
            )
        }
        let outcome = await PostingHarness.run(
            formPage: page, formURL: try PostingCapture.pageURL(formID), answer: try PostingCapture.answer("W10")
        ) { flow, form async throws(PostingError) in
            #expect(form.form.field(named: "delete")?.isChecked == true)
            switch form.shape {
            case .newTopic: return try await flow.newTopic(subject: "s", text: "t", with: form)
            case .newPrivateMessage: return try await flow.newPrivateMessage(to: "user1", subject: "s", text: "t", with: form)
            default: return try await flow.reply("t", with: form)
            }
        }
        let body = try #require(outcome.body)
        #expect(!PostingHarness.pairs(of: body).contains { $0.name == "delete" })
    }

    @Test("A form page reached on another hardware.fr host is refused before anything is posted")
    func formServedOffForum() async throws {
        let html = try Capture.page("R47b-mp-reply-composer")
        let redirected = HTTPResponse(
            statusCode: 200, headers: ["Content-Type": "text/html; charset=utf-8"],
            url: PostingCapture.url("https://www.hardware.fr/message.php"), body: Data(html.utf8)
        )
        let outcome = await PostingHarness.run(
            formPage: .success(redirected), formURL: try PostingCapture.pageURL("R47b"), write: { flow, form async throws(PostingError) in
                try await flow.reply("t", with: form)
            }
        )
        #expect(outcome.error == .invalidFormURL)
        #expect(outcome.requests.count == 1)
        #expect(outcome.hashChecks.isEmpty)
    }
}
