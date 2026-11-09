/// A group roster change HFR confirmed (LOT-058).
public struct GroupRosterChange: Sendable, Equatable {
    /// The reply that carried the change: HFR's success answer is the ordinary reply's (`W74`, `W75`).
    public let posting: PostingResult
    /// The other members as the owner's composer serves them after the change, in HFR's order, which is not the order sent
    /// (`W73`, `R127`). Nil when it could not be read: the change stands, the composer has to be loaded again to know.
    public let members: [String]?
}
