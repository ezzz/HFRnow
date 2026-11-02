import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
import Testing
@testable import HFRClient

/// Public topic writes captured in run 8 (#396): a new topic (`W40`), a first-post edit adding a poll (`W41`) and the
/// first-post delete that removed the topic (`W49`, then `R92`). Their forms were not captured as served, so the closest
/// captured forms stand in (`R45a` new topic, `R63b` first-post edit of another own topic); the bodies are compared by
/// field names in order, the answers are HFR's own bytes.
@Suite("Posting flow: public new topic and topic delete")
struct PostingTopicCaptureTests {
    /// Boxes the captures sent with legacy semantics (`"0"` when unchecked): a browser sends only the checked ones.
    private static let boxes: Set<String> = ["have_sondage", "allowvisitor", "signature", "smiley", "emaill", "delete"]
    private static let editURL = "https://forum.hardware.fr/bdd.php?config=hfr.inc"

    /// A write that must not run: the form load fails first.
    private static let noWrite: PostingHarness.Write = { _, _ async throws(PostingError) -> PostingResult in
        Issue.record("no form expected")
        throw .missingAction
    }

    private func names(_ body: String?, droppingBoxes: Bool = false) -> [String] {
        PostingHarness.pairs(of: body ?? "").map(\.name).filter { !droppingBoxes || !Self.boxes.contains($0) }
    }

    private func capturedNames(_ id: String) throws -> [String] {
        try #require(try Capture.meta(id).requestFields).filter { !Self.boxes.contains($0) }
    }

    @Test("W40: a new topic is confirmed; HFR refreshes to the category list and names no topic id")
    func newTopic() async throws {
        let outcome = try await PostingHarness.run(form: "R45a", answer: "W40") { flow, form async throws(PostingError) in
            try await flow.newTopic(subject: "fixture-test", text: "text", options: [.signature: true], with: form)
        }
        // Same composer layout as W40's (sent from Programmation › iOS with the signature box checked): same fields in order.
        #expect(names(outcome.body) == (try #require(try Capture.meta("W40").requestFields)))
        let result = try outcome.result.get()
        #expect(result.action == .newTopic)
        #expect(result.message == "Votre message a été posté avec succès !")
        #expect(result.refreshURL.absoluteString == "https://forum.hardware.fr/hfr/Programmation/liste_sujet-1.htm")
        #expect(result.refreshAnchor == nil)
        #expect(result.postNumber == nil)
        // W40 posted `cat=10`: the list HFR refreshes to is that category's, without a sub-category.
        let list = HFRTopicListLink(category: .forum(10), subcategory: nil, page: 1, filter: .all)
        #expect(result.refreshRoute == .topicList(list))
        #expect(!result.deletedWholeTopic)
    }

    @Test("W41: a first-post edit from R63b sends the poll fields as served and is confirmed")
    func firstPostEditWithPollFields() async throws {
        let outcome = try await PostingHarness.run(form: "R63b", answer: "W41") { flow, form async throws(PostingError) in
            try await flow.edit("Text removed.", with: form)
        }
        let post = try #require(outcome.post)
        #expect(post.url.absoluteString == Self.editURL)
        #expect(post.redirectPolicy == .doNotFollow)
        #expect(names(outcome.body, droppingBoxes: true) == (try capturedNames("W41")))
        #expect(!names(outcome.body).contains("delete"))
        let result = try outcome.result.get()
        #expect(result.action == .edit)
        #expect(result.message == "Votre message a été édité avec succès !")
        #expect(result.refreshAnchor == "t9910000001")
        #expect(result.postNumber == 9_910_000_001)
        #expect(!result.deletedWholeTopic)
    }

    @Test("W49: the public first-post delete from R63b needs the whole-topic confirmation, then is reported as a topic delete")
    func firstPostDeleteDeletesTopic() async throws {
        let refused = try await PostingHarness.run(form: "R63b", answer: "W49") { flow, form async throws(PostingError) in
            #expect(form.deletesWholeTopic)
            return try await flow.delete(with: form, isFirstPost: true)
        }
        #expect(refused.error == .wholeTopicDeletionNotConfirmed)
        #expect(refused.post == nil)

        let outcome = try await PostingHarness.run(form: "R63b", answer: "W49") { flow, form async throws(PostingError) in
            try await flow.delete(with: form, isFirstPost: true, confirmingWholeTopic: true)
        }
        #expect(try #require(outcome.post).url.absoluteString == Self.editURL)
        let pairs = PostingHarness.pairs(of: try #require(outcome.body))
        #expect(pairs.filter { $0.name == "delete" }.map(\.value) == ["1"])
        #expect(names(outcome.body, droppingBoxes: true) == (try capturedNames("W49")))
        let result = try outcome.result.get()
        #expect(result.action == .delete)
        #expect(result.message == "Message effacé avec succès !")
        #expect(result.refreshAnchor == nil)
        #expect(result.postNumber == 9_910_000_001)
        // The sub-category list of the deleted topic (R92: /hfr/Programmation/iOS/…, cat=10 in W49's body).
        let list = HFRTopicListLink(category: .forum(10), subcategory: .pathSegment("iOS"), page: 1, filter: .all)
        #expect(result.refreshRoute == .topicList(list))
        #expect(result.deletedWholeTopic)
    }

    @Test("A delete is a topic delete only when HFR refreshes to a list: W19 and W49 yes, W16a and W32 (later posts) no",
          arguments: [("W19", true), ("W49", true), ("W16a", false), ("W32", false)])
    func deleteAnswerTellsTopicDelete(answerID: String, deletesTopic: Bool) throws {
        let response = try PostingCapture.answer(answerID).get()
        let result = try PostingFlow.confirmation(of: .delete, in: response, requestURL: response.url, postNumber: 1)
        #expect(result.deletedWholeTopic == deletesTopic)
    }

    @Test("Another write's answer pointing at a list is never a topic delete: W40 read as a new topic, W10 as a new MP")
    func listRefreshOfOtherWrites() throws {
        for (answerID, action) in [("W40", PostingAction.newTopic), ("W10", .newPrivateMessage)] {
            let response = try PostingCapture.answer(answerID).get()
            let result = try PostingFlow.confirmation(of: action, in: response, requestURL: response.url, postNumber: nil)
            #expect(!result.deletedWholeTopic)
        }
    }

    @Test("R92: after the topic delete its page is a 404; a form load there fails, sends nothing and records no token")
    func deletedTopicPage() async throws {
        let meta = try Capture.meta("R92")
        let url = PostingCapture.url(meta.url)
        let page = try Capture.response("R92-topic-after-first-post-delete-404", url: url, status: meta.status)
        let outcome = await PostingHarness.run(formPage: .success(page), formURL: url, write: Self.noWrite)
        #expect(outcome.error == .network(.httpStatus(code: 404, url: url)))
        #expect(outcome.requests.count == 1)
        #expect(outcome.post == nil)
        #expect(outcome.hashChecks.isEmpty)
    }
}
