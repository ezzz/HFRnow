/// The poll of a topic page, either open for voting or showing results.
public struct Poll: Sendable, Hashable, Codable {
    /// What the page lets the user do.
    public enum Kind: Sendable, Hashable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        /// Voting form: answers and the hidden inputs to send back with the vote.
        case votable(options: [PollOption], hiddenFields: [String: String])
        /// Results only (already voted, or poll closed).
        case results([PollResult])

        /// Summary that never prints the hidden fields (they hold the `hash_check` token).
        public var description: String {
            switch self {
            case .votable(let options, let hiddenFields):
                "votable(\(options.count) options, \(hiddenFields.count) hidden fields, values redacted)"
            case .results(let lines):
                "results(\(lines.count) lines)"
            }
        }

        /// Same as `description`.
        public var debugDescription: String { description }

        /// Reflection (`dump`, debugger) shows the summary instead of the stored values.
        public var customMirror: Mirror {
            Mirror(self, children: ["summary": description], displayStyle: .enum)
        }
    }

    /// Poll question.
    public var question: String
    /// Footer text (end date, total), nil when absent.
    public var footer: String?
    /// How many answers may be selected (the initializer raises values below 1 to 1).
    public var maxChoices: Int
    /// Voting form or results.
    public var kind: Kind

    /// Creates a poll; `maxChoices` is raised to at least 1.
    public init(question: String, footer: String? = nil, maxChoices: Int = 1, kind: Kind) {
        self.question = question
        self.footer = footer
        self.maxChoices = max(1, maxChoices)
        self.kind = kind
    }
}
