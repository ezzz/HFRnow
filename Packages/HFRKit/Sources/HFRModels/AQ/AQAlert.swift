/// An existing AQ of a topic, from `getAlertesByTopic.php` (format verified on the live host, `T02`; HFR-PROTOCOL §8).
public struct AQAlert: Sendable, Hashable, Identifiable, Codable {
    /// AQ number; sending it again reports another message under the same AQ.
    public var id: Int
    /// AQ title.
    public var title: String
    /// Pseudo of the initiator.
    public var initiator: String
    /// Creation date as served (`dd-MM-yyyy`).
    public var dateText: String
    /// Numbers of the reported messages.
    public var postIDs: [Int]

    /// Creates an alert.
    public init(id: Int, title: String, initiator: String, dateText: String, postIDs: [Int]) {
        self.id = id
        self.title = title
        self.initiator = initiator
        self.dateText = dateText
        self.postIDs = postIDs
    }
}
