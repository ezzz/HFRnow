import Foundation
import HFRModels
import HFRNetwork
import Testing
@testable import HFRClient

/// Checks made before anything is posted: each refusal sends the form request only, never the POST.
@Suite("Posting flow: local checks")
struct PostingInputTests {
    private func expectNoPost(_ outcome: PostingHarness.Outcome, _ error: PostingError) {
        #expect(outcome.error == error)
        #expect(outcome.requests.count == 1)
        #expect(outcome.post == nil)
    }

    @Test("W12: characters outside the BMP are refused (HFR would cut the text there and answer success)")
    func nonBMPText() async throws {
        let outcome = try await PostingHarness.run(form: "R47b") { flow, form async throws(PostingError) in
            try await flow.reply("fixture-test 3, before 😀 after 😀 and 👍🏽, é ☺ ❤ kept", with: form)
        }
        expectNoPost(outcome, .unsupportedCharacters(.text, ["😀", "👍🏽"]))
    }

    @Test("Non-BMP characters in a subject or a recipient are refused too")
    func nonBMPSubjectAndRecipient() async throws {
        let subject = try await PostingHarness.run(form: "R45b") { flow, form async throws(PostingError) in
            try await flow.newPrivateMessage(to: "user1", subject: "hi 🎉", text: "text", with: form)
        }
        expectNoPost(subject, .unsupportedCharacters(.subject, ["🎉"]))
        let recipient = try await PostingHarness.run(form: "R45b") { flow, form async throws(PostingError) in
            try await flow.newPrivateMessage(to: "user𝟙", subject: "s", text: "text", with: form)
        }
        expectNoPost(recipient, .unsupportedCharacters(.recipient, ["𝟙"]))
    }

    @Test("W17a: an empty or blank text is refused locally", arguments: ["", " \n\t "])
    func emptyText(text: String) async throws {
        let outcome = try await PostingHarness.run(form: "R47b") { flow, form async throws(PostingError) in
            try await flow.reply(text, with: form)
        }
        expectNoPost(outcome, .emptyInput(.text))
    }

    @Test("A new thread needs a subject and a recipient")
    func emptySubjectAndRecipient() async throws {
        let subject = try await PostingHarness.run(form: "R45a") { flow, form async throws(PostingError) in
            try await flow.newTopic(subject: " ", text: "text", with: form)
        }
        expectNoPost(subject, .emptyInput(.subject))
        let recipient = try await PostingHarness.run(form: "R45b") { flow, form async throws(PostingError) in
            try await flow.newPrivateMessage(to: "", subject: "s", text: "text", with: form)
        }
        expectNoPost(recipient, .emptyInput(.recipient))
    }

    @Test("Shapes read from the captured forms")
    func shapes() async throws {
        let expected: [String: PostingForm.Shape] = [
            "R40a": .reply, "R41a": .reply, "R41b": .reply, "R42": .reply, "R47a": .reply, "R47b": .reply, "R47c": .reply,
            "R47u1": .reply, "R45a": .newTopic, "R45b": .newPrivateMessage, "R43a": .edit, "R43b": .edit, "R43c": .edit, "R44": .edit
        ]
        for (id, shape) in expected {
            let session = ScriptedPostingSession([try PostingCapture.form(id)])
            let form = try await PostingFlow().loadForm(at: try PostingCapture.pageURL(id), through: session)
            #expect(form.shape == shape, "\(id)")
            #expect(form.deletesWholeTopic == (id == "R43a"), "\(id)")
            #expect(form.canDelete == ["R43a", "R43b", "R43c"].contains(id), "\(id)")
        }
    }

    @Test("A write refuses another composer's form")
    func formMismatch() async throws {
        let newTopic = try await PostingHarness.run(form: "R45a") { flow, form async throws(PostingError) in
            try await flow.reply("text", with: form)
        }
        expectNoPost(newTopic, .formMismatch(expected: .reply, actual: .newTopic))
        let reply = try await PostingHarness.run(form: "R47b") { flow, form async throws(PostingError) in
            try await flow.delete(with: form)
        }
        expectNoPost(reply, .formMismatch(expected: .edit, actual: .reply))
        let editForm = try await PostingHarness.run(form: "R44") { flow, form async throws(PostingError) in
            try await flow.reply("text", with: form)
        }
        expectNoPost(editForm, .formMismatch(expected: .reply, actual: .edit))
    }

    @Test("R44: another account's message has no delete box")
    func deleteNotOffered() async throws {
        let outcome = try await PostingHarness.run(form: "R44") { flow, form async throws(PostingError) in
            try await flow.delete(with: form, confirmingWholeTopic: true)
        }
        expectNoPost(outcome, .deleteNotOffered)
    }

    @Test("R43a: deleting the first post without confirming the whole thread sends nothing")
    func wholeTopicNotConfirmed() async throws {
        let outcome = try await PostingHarness.run(form: "R43a") { flow, form async throws(PostingError) in
            try await flow.delete(with: form)
        }
        expectNoPost(outcome, .wholeTopicDeletionNotConfirmed)
    }

    @Test("Either sign of a first post asks for confirmation: the subject field or the delete label")
    func wholeTopicSigns() async throws {
        // R43a with its subject hidden keeps the label; R43b with the first-post label keeps its hidden subject.
        let hiddenSubject = try PostingHarness.editedForm("R43a") {
            $0.replacing(
                "<input maxlength=\"70\" accesskey=\"t\" size=\"50\" name=\"sujet\"", with: "<input type=\"hidden\" name=\"sujet\""
            )
        }
        let label = try PostingHarness.editedForm("R43b") {
            $0.replacing("Effacer ce message", with: "Effacer l'intégralité du sujet")
        }
        for (page, id) in [(hiddenSubject, "R43a"), (label, "R43b")] {
            let formURL = try PostingCapture.pageURL(id)
            let outcome = await PostingHarness.run(formPage: page, formURL: formURL) { flow, form async throws(PostingError) in
                #expect(form.deletesWholeTopic, "\(id)")
                #expect(!form.form.isSubjectEditable, "\(id): only the label is left")
                return try await flow.delete(with: form)
            }
            expectNoPost(outcome, .wholeTopicDeletionNotConfirmed)
        }
    }

    @Test("An edit never sends the delete box, even when the page serves it checked")
    func editNeverDeletes() async throws {
        let page = try PostingHarness.editedForm("R43b") {
            $0.replacing("name=\"delete\" id=\"delete\"", with: "name=\"delete\" id=\"delete\" checked=\"checked\"")
        }
        let outcome = await PostingHarness.run(
            formPage: page, formURL: try PostingCapture.pageURL("R43b"), answer: try PostingCapture.answer("W15")
        ) { flow, form async throws(PostingError) in
            #expect(form.form.field(named: "delete")?.isChecked == true)
            return try await flow.edit("text", with: form)
        }
        #expect(outcome.body?.contains("delete") == false)
        #expect(outcome.error == nil)
    }

    @Test("A subject is refused on a later post's edit form")
    func subjectNotEditable() async throws {
        let outcome = try await PostingHarness.run(form: "R43b") { flow, form async throws(PostingError) in
            try await flow.edit("text", subject: "renamed", with: form)
        }
        expectNoPost(outcome, .subjectNotEditable)
    }

    @Test("A sub-category must be one of the form's options")
    func unknownSubcategory() async throws {
        let outcome = try await PostingHarness.run(form: "R45a") { flow, form async throws(PostingError) in
            try await flow.newTopic(subject: "s", subcategory: "999999", text: "text", with: form)
        }
        expectNoPost(outcome, .unknownSubcategory)
    }

    @Test("An option the form does not offer is refused")
    func optionNotOffered() async throws {
        let page = try PostingHarness.editedForm("R47b") {
            $0.replacing("name=\"emaill\"", with: "name=\"other\"")
        }
        let formURL = try PostingCapture.pageURL("R47b")
        let outcome = await PostingHarness.run(formPage: page, formURL: formURL) { flow, form async throws(PostingError) in
            try await flow.reply("text", options: [.emailNotification: true], with: form)
        }
        expectNoPost(outcome, .optionNotOffered(.emailNotification))
    }
}
