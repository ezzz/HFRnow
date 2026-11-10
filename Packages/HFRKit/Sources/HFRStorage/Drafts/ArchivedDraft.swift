import Foundation

/// Where an archived reply came from (legacy `ReplyDraftSource`, `AnswerView.swift:103-121` @ 87fe0d1c).
public enum ArchivedDraftSource: String, Sendable, Hashable, Codable {
    /// Typed in the composer ("Réponse rapide").
    case quickReply
    /// Started from a quote ("Citation").
    case quote
}

/// A reply set aside in a topic, to pick up again later (LOT-101).
public struct ArchivedDraft: Sendable, Hashable, Identifiable {
    /// Identity inside the topic.
    public var id: UUID
    /// The text as it was written.
    public var text: String
    /// Where it came from.
    public var source: ArchivedDraftSource
    /// When it was set aside.
    public var archivedAt: Date

    /// Creates an archived draft.
    public init(id: UUID, text: String, source: ArchivedDraftSource, archivedAt: Date) {
        self.id = id
        self.text = text
        self.source = source
        self.archivedAt = archivedAt
    }
}
