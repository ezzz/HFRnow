import Foundation
import HFRModels

// Port of HFRswift/Swift/TopicPollDraft.swift:4-53 (TopicPollDraft) @ 87fe0d1c. Differences: a question or an answer with a line
// break or a character outside the Basic Multilingual Plane is refused (one-line inputs; HFR cuts the text there, decision Q-3).
/// A poll to add to a topic through its first post's edit form (LOT-100): what the user wrote, checked before anything is sent.
public struct PollDraft: Sendable, Hashable {
    /// The question, `textreponse0`.
    public var question: String
    /// The answer slots, in order; blank ones are not sent and do not count.
    public var answers: [String]
    /// How many answers a member may choose, `max_votes` (1 to the number of answers).
    public var maxChoices: Int
    /// Members not logged in may vote too, the `allowvisitor` box.
    public var allowsVisitors: Bool
    /// When the poll closes; nil leaves it open (the date fields are sent empty, as in `W41`).
    public var closingDate: Date?

    /// A poll with two empty answers, one choice, members only and no closing date (legacy's defaults).
    public init(
        question: String = "", answers: [String] = ["", ""], maxChoices: Int = 1, allowsVisitors: Bool = false, closingDate: Date? = nil
    ) {
        self.question = question
        self.answers = answers
        self.maxChoices = maxChoices
        self.allowsVisitors = allowsVisitors
        self.closingDate = closingDate
    }

    /// The form's answer inputs: `textreponse1` to `textreponse10` (`R63b`, `R170a`).
    public static let maximumAnswers = 10
    /// Every poll input has `maxlength="255"` (`R63b`, `R170a`), counted in UTF-16 code units as a browser does.
    public static let maximumLength = 255

    /// The answers that are sent: trimmed, blank ones dropped, in order.
    public var filledAnswers: [String] {
        answers.map(Self.trimmed).filter { !$0.isEmpty }
    }

    /// The first thing that stops this poll from being sent, in legacy's order; nil when it can be sent.
    public func problem(now: Date = Date()) -> PollProblem? {
        let question = Self.trimmed(question)
        if question.isEmpty { return .emptyQuestion }
        if let problem = Self.lineProblem(question) { return .question(problem) }
        let filled = filledAnswers
        if filled.count < 2 { return .tooFewAnswers }
        if answers.count > Self.maximumAnswers { return .tooManyAnswers }
        for answer in filled {
            if let problem = Self.lineProblem(answer) { return .answer(problem) }
        }
        if !(1...filled.count).contains(maxChoices) { return .choicesOutOfRange }
        if let closingDate, closingDate <= now { return .closingDateNotInFuture }
        return nil
    }

    /// The text inputs this poll fills, by name: the question, the answers packed from `textreponse1`, `max_votes`, and the
    /// closing date in `calendar` (legacy formats, `TopicPollDraft.swift:38-48`). Boxes are not included.
    func fields(calendar: Calendar) -> [String: String] {
        var fields = ["textreponse0": Self.trimmed(question), "max_votes": String(maxChoices)]
        for (index, answer) in filledAnswers.enumerated() {
            fields["textreponse\(index + 1)"] = answer
        }
        if let closingDate {
            let parts = calendar.dateComponents([.day, .month, .year, .hour, .minute], from: closingDate)
            fields["jour"] = Self.twoDigits(parts.day)
            fields["mois"] = Self.twoDigits(parts.month)
            fields["annee"] = String(parts.year ?? 0)
            fields["heure"] = Self.twoDigits(parts.hour)
            fields["minute"] = Self.twoDigits(parts.minute)
        }
        return fields
    }

    /// The date inputs, filled only with a closing date.
    static let dateFields = ["jour", "mois", "annee", "heure", "minute"]

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func twoDigits(_ value: Int?) -> String {
        let value = value ?? 0
        return value < 10 ? "0\(value)" : String(value)
    }

    /// What is wrong with one trimmed line, if anything.
    private static func lineProblem(_ value: String) -> PollProblem.Line? {
        if value.utf16.count > maximumLength { return .tooLong }
        if value.contains(where: \.isNewline) { return .lineBreak }
        let refused = PostCharacterCheck.truncatingCharacters(in: value)
        return refused.isEmpty ? nil : .unsupportedCharacters(refused)
    }
}

/// Why a poll cannot be sent.
public enum PollProblem: Sendable, Hashable {
    /// What is wrong with the question or an answer.
    public enum Line: Sendable, Hashable {
        /// Longer than the input's 255 UTF-16 code units.
        case tooLong
        /// A one-line input cannot hold a line break.
        case lineBreak
        /// Characters HFR would cut the text at (decision Q-3), distinct, in order.
        case unsupportedCharacters([Character])
    }

    /// The question is blank.
    case emptyQuestion
    /// The question cannot be sent as written.
    case question(Line)
    /// Fewer than two answers are filled.
    case tooFewAnswers
    /// More answer slots than the form's ten.
    case tooManyAnswers
    /// An answer cannot be sent as written.
    case answer(Line)
    /// The number of choices is not between 1 and the number of filled answers.
    case choicesOutOfRange
    /// The closing date is not in the future.
    case closingDateNotInFuture
}

extension ForumForm {
    /// True when this form can add a poll: an unchecked `have_sondage` box and the question input `textreponse0` (legacy's
    /// test, `HFRswift/Swift/ReplyService.swift:279-281` @ 87fe0d1c). A public first post's edit form has them (`R63b`); the
    /// new-topic and new-poll forms have no `have_sondage` (`R45a`, `R170a`), nor do later posts (`R62a`) or private threads.
    public var offersPollCreation: Bool {
        guard let box = field(named: PollDraft.boxField), box.kind == .checkbox, !box.isChecked else { return false }
        return field(named: "textreponse0") != nil
    }
}

extension PollDraft {
    /// The box that adds the poll.
    static let boxField = "have_sondage"
    /// The box that lets visitors vote.
    static let visitorsField = "allowvisitor"
}
