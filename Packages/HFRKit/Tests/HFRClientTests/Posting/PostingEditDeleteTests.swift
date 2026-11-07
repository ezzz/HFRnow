import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
import Testing
@testable import HFRClient

/// LOT-088: what the app sends for "Editer" and "Supprimer", on the captured forms and HFR's own answers.
@Suite("Posting flow: edit and delete from the message menu")
struct PostingEditDeleteTests {
    private func value(_ name: String, in body: String?) -> [String] {
        PostingHarness.pairs(of: body ?? "").filter { $0.name == name }.map(\.value)
    }

    @Test("W34: a first post sent back with its own title and sub-category keeps W34's fields and is confirmed")
    func firstPostEditAsServed() async throws {
        let outcome = try await PostingHarness.run(form: "R63b", answer: "W34") { flow, form async throws(PostingError) in
            try await flow.edit("Text.", subject: "Own topic subject", subcategory: "173", with: form)
        }
        let boxes: Set<String> = ["signature"]
        let captured = try #require(try Capture.meta("W34").requestFields).filter { !boxes.contains($0) }
        #expect(PostingHarness.pairs(of: outcome.body ?? "").map(\.name).filter { !boxes.contains($0) } == captured)
        #expect(value("subcat", in: outcome.body) == ["173"])
        #expect(value("sujet", in: outcome.body) == ["Own topic subject"])
        #expect(try outcome.result.get().refreshAnchor == "t9910000001")
    }

    @Test("A first-post edit sends the title and the sub-category chosen, once each and in the select's place")
    func firstPostEditChangesTitleAndSubcategory() async throws {
        let served = try await PostingHarness.run(form: "R63b", answer: "W34") { flow, form async throws(PostingError) in
            try await flow.edit("Text.", with: form)
        }
        let outcome = try await PostingHarness.run(form: "R63b", answer: "W34") { flow, form async throws(PostingError) in
            try await flow.edit("Text.", subject: "New title", subcategory: "169", with: form)
        }
        #expect(value("subcat", in: outcome.body) == ["169"])
        #expect(value("sujet", in: outcome.body) == ["New title"])
        // The form's order is untouched: the choice replaces the select's value, it adds no field.
        #expect(PostingHarness.pairs(of: outcome.body ?? "").map(\.name) == PostingHarness.pairs(of: served.body ?? "").map(\.name))
    }

    @Test("\"Aucune\" is a choice like any other: its empty value is sent")
    func firstPostEditChoosesNoSubcategory() async throws {
        let outcome = try await PostingHarness.run(form: "R63b", answer: "W34") { flow, form async throws(PostingError) in
            #expect(form.form.subcategories.first?.value == "")
            return try await flow.edit("Text.", subcategory: "", with: form)
        }
        #expect(value("subcat", in: outcome.body) == [""])
    }

    @Test("A sub-category the form does not offer is refused before anything is sent")
    func editRefusesAnUnknownSubcategory() async throws {
        let outcome = try await PostingHarness.run(form: "R63b", answer: "W34") { flow, form async throws(PostingError) in
            try await flow.edit("Text.", subcategory: "999", with: form)
        }
        #expect(outcome.error == .unknownSubcategory)
        #expect(outcome.post == nil)
    }

    @Test("A later post has no select: without a choice its hidden sub-category goes back as served (W31)")
    func laterPostEditKeepsItsHiddenSubcategory() async throws {
        let outcome = try await PostingHarness.run(form: "R62a", answer: "W31") { flow, form async throws(PostingError) in
            try await flow.edit("Text.", with: form)
        }
        #expect(value("subcat", in: outcome.body) == ["430"])
        #expect(!PostingHarness.pairs(of: outcome.body ?? "").map(\.name).contains("delete"))
        #expect(try outcome.result.get().postNumber == 75_493_617)
    }

    @Test("W32: a later post of a public topic is deleted with the form's box, without a whole-topic confirmation")
    func laterPostDeletePublic() async throws {
        let outcome = try await PostingHarness.run(form: "R62a", answer: "W32") { flow, form async throws(PostingError) in
            #expect(form.requiresWholeTopicConfirmation())
            return try await flow.deleteLaterPost(75_493_617, with: form)
        }
        #expect(value("delete", in: outcome.body) == ["1"])
        let result = try outcome.result.get()
        #expect(result.action == .delete)
        #expect(result.message == "Message effacé avec succès !")
        #expect(!result.deletedWholeTopic)
    }

    @Test("W16a: a later post of a private thread")
    func laterPostDeletePrivate() async throws {
        let outcome = try await PostingHarness.run(form: "R43b", answer: "W16a") { flow, form async throws(PostingError) in
            try await flow.deleteLaterPost(1_980_875_030, with: form)
        }
        #expect(try outcome.result.get().action == .delete)
    }

    @Test("A first post is refused with nothing sent, public or private, whatever the caller says", arguments: [
        ("R63b", 9_910_000_001), ("R43a", 1_980_875_029)
    ])
    func firstPostIsNeverDeleted(form name: String, post: Int) async throws {
        let outcome = try await PostingHarness.run(form: name, answer: "W49") { flow, form async throws(PostingError) in
            try await flow.deleteLaterPost(post, with: form)
        }
        #expect(outcome.error == .wholeTopicDeletionNotConfirmed)
        #expect(outcome.post == nil)
    }

    @Test("The form of another message is never posted")
    func deleteRefusesAnotherMessagesForm() async throws {
        let outcome = try await PostingHarness.run(form: "R62a", answer: "W32") { flow, form async throws(PostingError) in
            try await flow.deleteLaterPost(1, with: form)
        }
        #expect(outcome.error == .unsupportedForm(reason: "edit form of another message"))
        #expect(outcome.post == nil)
    }

    @Test("An edit form without the box (another account's message, R44) deletes nothing")
    func deleteNotOffered() async throws {
        let outcome = try await PostingHarness.run(form: "R44", answer: "W32") { flow, form async throws(PostingError) in
            try await flow.deleteLaterPost(try await Self.number(of: form), with: form)
        }
        #expect(outcome.error == .deleteNotOffered)
        #expect(outcome.post == nil)
    }

    private static func number(of form: PostingForm) async throws(PostingError) -> Int {
        guard let number = form.postNumber else { throw .missingAction }
        return number
    }
}
