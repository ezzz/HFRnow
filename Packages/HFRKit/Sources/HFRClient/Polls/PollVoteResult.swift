import Foundation
import HFRModels

/// HFR's confirmation of a poll vote.
public struct PollVoteResult: Sendable, Equatable {
    /// The topic of the poll, read from the form's `cat` and `numeropost`.
    public var topic: TopicID
    /// The answer voted for: its 1-based position, the `PollOption.id`.
    public var choice: Int
    /// HFR's sentence, "Votre vote a bien été pris en compte !".
    public var message: String
    /// The page of the topic HFR refreshes to (page 1 in `W42`, whose form had `page=1`; whether HFR echoes another
    /// form page is pending capture); reload it to show the results. Always `https` on `forum.hardware.fr` (LOT-037).
    public var refreshURL: URL

    /// Creates a result.
    public init(topic: TopicID, choice: Int, message: String, refreshURL: URL) {
        self.topic = topic
        self.choice = choice
        self.message = message
        self.refreshURL = refreshURL
    }
}
