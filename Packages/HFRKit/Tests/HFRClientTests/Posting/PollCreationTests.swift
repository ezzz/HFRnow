import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
import Testing
@testable import HFRClient

/// LOT-100: a poll added through a public first post's edit form (`R63b`), answered by `W41`; refused locally everywhere else.
@Suite("Posting flow: poll creation")
struct PollCreationTests {
    /// `W41`'s poll: question, two answers, one choice, members only, no closing date.
    private static let w41Poll = PollDraft(question: "fixture-test poll", answers: ["A", "B"])

    private static func edit(_ poll: PollDraft, form: String = "R63b") async throws -> PostingHarness.Outcome {
        try await PostingHarness.run(form: form, answer: "W41") { flow, form async throws(PostingError) in
            try await flow.edit("Text removed.", poll: poll, with: form)
        }
    }

    private static func value(_ name: String, in outcome: PostingHarness.Outcome) -> String? {
        PostingHarness.pairs(of: outcome.body ?? "").first { $0.name == name }?.value
    }

    @Test("W41: the poll of R63b is sent as W41 sent it (boxes as a browser sends them) and the edit is confirmed")
    func w41Body() async throws {
        let outcome = try await Self.edit(Self.w41Poll)
        // W41 was sent from another own topic's edit form than R63b's: its token, topic, category and sub-category differ.
        let ownTopic: Set<String> = ["hash_check", "post", "cat", "subcat"]
        let sent = PostingHarness.pairs(of: try #require(outcome.body)).filter { !ownTopic.contains($0.name) }
        // W41 sent every box with legacy semantics ("0" when unchecked); a browser leaves an unchecked box out.
        let captured = PostingHarness.pairs(of: try #require(try Capture.meta("W41").requestBody))
            .filter { !ownTopic.contains($0.name) && !($0.value == "0" && Self.boxes.contains($0.name)) }
        #expect(sent.map(\.name) == captured.map(\.name))
        #expect(sent.map(\.value) == captured.map(\.value))
        let result = try outcome.result.get()
        #expect(result.action == .edit)
        #expect(result.message == "Votre message a été édité avec succès !")
    }

    private static let boxes: Set<String> = ["allowvisitor", "smiley", "emaill", "delete"]

    @Test("Without a poll, the R63b edit sends no poll box nor poll text")
    func noPoll() async throws {
        let outcome = try await PostingHarness.run(form: "R63b", answer: "W41") { flow, form async throws(PostingError) in
            try await flow.edit("Text removed.", with: form)
        }
        #expect(Self.value("have_sondage", in: outcome) == nil)
        #expect(Self.value("textreponse0", in: outcome) == "")
        #expect(Self.value("max_votes", in: outcome) == "1")
    }

    @Test("Which captured forms offer a poll: only the public first post's edit form",
          arguments: [("R63b", true), ("R45a", false), ("R62a", false), ("R43a", false), ("R40a", false), ("R61b", false)])
    func formsOfferingPoll(form: String, offers: Bool) async throws {
        let page = try PostingCapture.form(form).get()
        let parsed = try HopFormParser.parse(page.decodedText().text, pageURL: page.url)
        #expect(parsed.offersPollCreation == offers)
    }

    @Test("R170a, the new-poll form of a topic list, has no have_sondage box: no poll through it")
    func newPollFormOffersNone() throws {
        let html = try Capture.page("R170a-new-poll-form")
        let pageURL = try #require(URL(string: "https://forum.hardware.fr/hfr/Discussions/nouveau_sondage.htm"))
        let parsed = try HopFormParser.parse(html, pageURL: pageURL)
        #expect(parsed.field(named: "textreponse0") != nil)
        #expect(!parsed.offersPollCreation)
    }

    @Test("A poll on a later post's edit form is refused before anything is sent")
    func laterPostRefused() async throws {
        let outcome = try await Self.edit(Self.w41Poll, form: "R62a")
        #expect(outcome.error == .pollNotOffered)
        #expect(outcome.post == nil)
    }

    @Test("A first post whose have_sondage box is served checked (a poll exists) refuses a new poll")
    func existingPollRefused() async throws {
        let page = try PostingHarness.editedForm("R63b") {
            $0.replacing(#"name="have_sondage" value="1""#, with: #"name="have_sondage" value="1" checked="checked""#)
        }
        let outcome = await PostingHarness.run(
            formPage: page, formURL: try PostingCapture.pageURL("R63b"), answer: try PostingCapture.answer("W41")
        ) { flow, form async throws(PostingError) in
            try await flow.edit("Text removed.", poll: Self.w41Poll, with: form)
        }
        #expect(outcome.error == .pollNotOffered)
        #expect(outcome.post == nil)
    }

    @Test("An invalid poll is refused with its problem and nothing is sent", arguments: [
        (PollDraft(question: "  ", answers: ["A", "B"]), PollProblem.emptyQuestion),
        (PollDraft(question: String(repeating: "q", count: 256), answers: ["A", "B"]), .question(.tooLong)),
        (PollDraft(question: "Q", answers: ["A", "  "]), .tooFewAnswers),
        (PollDraft(question: "Q", answers: Array(repeating: "A", count: 11)), .tooManyAnswers),
        (PollDraft(question: "Q", answers: ["A", String(repeating: "é", count: 256)]), .answer(.tooLong)),
        (PollDraft(question: "Q", answers: ["A", "B\nC"]), .answer(.lineBreak)),
        (PollDraft(question: "Q 😀", answers: ["A", "B"]), .question(.unsupportedCharacters(["😀"]))),
        (PollDraft(question: "Q", answers: ["A", "B"], maxChoices: 3), .choicesOutOfRange),
        (PollDraft(question: "Q", answers: ["A", "B"], maxChoices: 0), .choicesOutOfRange),
        (PollDraft(question: "Q", answers: ["A", "B"], closingDate: Date(timeIntervalSince1970: 946_684_800)), .closingDateNotInFuture)
    ])
    func invalidPoll(poll: PollDraft, problem: PollProblem) async throws {
        let outcome = try await Self.edit(poll)
        #expect(outcome.error == .invalidPoll(problem))
        #expect(outcome.post == nil)
    }

    @Test("Ten answers, blanks packed out, three choices, visitors and a closing date: every field at its place")
    func fullPoll() async throws {
        let closing = Date().addingTimeInterval(30 * 86_400)
        var answers = (1...9).map { "Answer \($0)" }
        answers.insert(" ", at: 2)
        let poll = PollDraft(question: " Q ", answers: answers, maxChoices: 3, allowsVisitors: true, closingDate: closing)
        let outcome = try await Self.edit(poll)
        #expect(outcome.error == nil)
        #expect(Self.value("have_sondage", in: outcome) == "1")
        #expect(Self.value("textreponse0", in: outcome) == "Q")
        #expect((1...9).map { Self.value("textreponse\($0)", in: outcome) } == (1...9).map { "Answer \($0)" })
        #expect(Self.value("textreponse10", in: outcome) == "")
        #expect(Self.value("allowvisitor", in: outcome) == "1")
        #expect(Self.value("max_votes", in: outcome) == "3")
        let parts = Calendar.current.dateComponents([.day, .month, .year, .hour, .minute], from: closing)
        #expect(Self.value("annee", in: outcome) == String(try #require(parts.year)))
        #expect(Self.value("jour", in: outcome)?.count == 2)
        #expect(Self.value("jour", in: outcome).flatMap { Int($0) } == parts.day)
        #expect(Self.value("minute", in: outcome).flatMap { Int($0) } == parts.minute)
        let names = PostingHarness.pairs(of: try #require(outcome.body)).map(\.name)
        #expect(names == (try #require(try Capture.meta("W41").requestFields)).filter { !["smiley", "emaill", "delete"].contains($0) })
    }

    @Test("The closing date is written day, month, year, hour, minute, zero-padded, in the calendar's time zone")
    func dateFields() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        // 2030-03-05 06:09 UTC is 07:09 in Paris (winter time).
        let poll = PollDraft(question: "Q", answers: ["A", "B"], closingDate: Date(timeIntervalSince1970: 1_898_921_340))
        let fields = poll.fields(calendar: calendar)
        #expect(fields["jour"] == "05")
        #expect(fields["mois"] == "03")
        #expect(fields["annee"] == "2030")
        #expect(fields["heure"] == "07")
        #expect(fields["minute"] == "09")
        #expect(PollDraft(question: "Q", answers: ["A", "B"]).fields(calendar: calendar)["jour"] == nil)
    }

    @Test("Legacy's limits: a 255-unit question and ten answers pass; the default draft is not sendable")
    func limits() {
        #expect(PollDraft(question: String(repeating: "q", count: 255), answers: Array(repeating: "A", count: 10), maxChoices: 10)
            .problem() == nil)
        #expect(PollDraft().problem() == .emptyQuestion)
    }
}
