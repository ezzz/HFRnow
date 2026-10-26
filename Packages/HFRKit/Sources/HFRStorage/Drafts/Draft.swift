import Foundation

/// An unsent message saved for a context.
public struct Draft: Sendable, Hashable, Codable {
    /// Where the draft belongs.
    public var context: DraftContext
    /// Normalised identifier of the account that was writing.
    public var account: String
    /// Message body.
    public var text: String
    /// Subject, for new topics and private messages.
    public var subject: String?
    /// When the draft was last saved; the time-to-live counts from here.
    public var updatedAt: Date

    /// Creates a draft.
    public init(context: DraftContext, account: String, text: String, subject: String? = nil, updatedAt: Date) {
        self.context = context
        self.account = account
        self.text = text
        self.subject = subject
        self.updatedAt = updatedAt
    }
}
