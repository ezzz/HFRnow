/// One conversation of the private messages list: the row as a topic summary, plus what only this list says.
public struct PrivateMessageThread: Sendable, Hashable, Identifiable, Codable {
    /// Same identity as the underlying row (`topic:prive-<post>`).
    public var id: String { summary.id }

    /// The row. Its `title` has the `[non lu]` marker removed; `readState` is the member's own state (`closedbp.gif`, "Nouveau message").
    public var summary: TopicSummary
    /// Pseudos that have not read the latest message yet, as HFR prints them in the `[non lu]` tooltip; empty when everyone has.
    /// A member's own unread state is `isUnread`: HFR's `[non lu]` is about the others.
    public var unreadBy: [String]
    /// Whether the thread shows the `[non lu]` marker, even when the tooltip names nobody.
    public var hasUnreadMarker: Bool
    /// Whether the others have not read it: the marker is shown or the tooltip names someone (computed, so it cannot disagree).
    public var isUnreadByOthers: Bool { hasUnreadMarker || !unreadBy.isEmpty }
    /// The other participants: the interlocutor of a one-to-one thread, the tooltip names of a group thread.
    /// Printed as served, so long pseudos may carry U+200B; compare with `HFRText.pseudoComparisonKey`.
    public var interlocutors: [String]
    /// A thread with several interlocutors ("Interlocuteurs multiples").
    public var isGroup: Bool

    /// Whether the member has an unread message in this thread.
    public var isUnread: Bool { summary.readState == .unread }

    /// Creates a conversation row.
    public init(
        summary: TopicSummary,
        unreadBy: [String] = [],
        isUnreadByOthers: Bool = false,
        interlocutors: [String] = [],
        isGroup: Bool = false
    ) {
        self.summary = summary
        self.unreadBy = unreadBy
        self.hasUnreadMarker = isUnreadByOthers
        self.interlocutors = interlocutors
        self.isGroup = isGroup
    }
}
