/// A votable answer of a poll.
public struct PollOption: Sendable, Hashable, Identifiable, Codable {
    /// 1-based position in the poll.
    public var id: Int
    /// Answer label.
    public var text: String
    /// Name of the form input that selects this answer.
    public var fieldName: String

    /// Creates an option.
    public init(id: Int, text: String, fieldName: String) {
        self.id = id
        self.text = text
        self.fieldName = fieldName
    }
}
