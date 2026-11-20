/// The Messages list's switch position (#899, `mp_list_segment`): every conversation, one-to-one ones, or group ones.
public enum MPSegment: String, Sendable, Codable, CaseIterable {
    /// "Tous": one-to-one and group conversations together (the default).
    case all
    /// One-to-one conversations ("MP").
    case oneToOne
    /// Group conversations ("MP multiples").
    case group

    /// Whether `thread` belongs to this segment (`PrivateMessageThread.isGroup`, legacy `MPListView.swift:376-377`).
    public func contains(_ thread: PrivateMessageThread) -> Bool {
        switch self {
        case .all: true
        case .oneToOne: !thread.isGroup
        case .group: thread.isGroup
        }
    }
}
