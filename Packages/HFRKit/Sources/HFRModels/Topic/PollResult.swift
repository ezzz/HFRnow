/// One line of poll results.
public struct PollResult: Sendable, Hashable, Identifiable, Codable {
    /// 1-based position in the poll.
    public var id: Int
    /// Answer label.
    public var label: String
    /// Share of votes, in percent (0...100).
    public var percentage: Double
    /// Number of votes.
    public var voteCount: Int

    /// Creates a result line.
    public init(id: Int, label: String, percentage: Double, voteCount: Int) {
        self.id = id
        self.label = label
        self.percentage = percentage
        self.voteCount = voteCount
    }
}
