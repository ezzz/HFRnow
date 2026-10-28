import Foundation

/// Where an account stopped reading a topic: small and made of integers, so it can later be mirrored between the
/// user's devices (LOT-172).
public struct ReadingPosition: Sendable, Hashable, Codable {
    /// Topic page, from 1.
    public var page: Int
    /// `numreponse` of the topmost message seen (the `t<numreponse>` anchor); nil when the page had none.
    public var messageNumber: Int?
    /// Vertical offset inside that message, in the app's own unit (points); nil means its top.
    public var offset: Int?
    /// When this position was recorded; the newest wins when two copies meet.
    public var updatedAt: Date

    /// Creates a position.
    public init(page: Int, messageNumber: Int? = nil, offset: Int? = nil, updatedAt: Date = Date()) {
        self.page = page
        self.messageNumber = messageNumber
        self.offset = offset
        self.updatedAt = updatedAt
    }

    /// Whether this position is past `other` in the topic; `updatedAt` plays no part.
    ///
    /// Message numbers win over pages when both positions have one: HFR numbers messages in posting order, and a page
    /// can hold earlier messages again after deletions. Without both numbers the page decides, then a known message
    /// beats an unknown one on the same page.
    public func isAhead(of other: ReadingPosition) -> Bool {
        if let mine = messageNumber, let theirs = other.messageNumber {
            if mine != theirs { return mine > theirs }
            return (offset ?? 0) > (other.offset ?? 0)
        }
        if page != other.page { return page > other.page }
        return messageNumber != nil && other.messageNumber == nil
    }

    /// True when every number is in range: page from 1, message number above 0, offset not negative.
    var isValid: Bool {
        page >= 1 && (messageNumber ?? 1) > 0 && (offset ?? 0) >= 0
    }
}
