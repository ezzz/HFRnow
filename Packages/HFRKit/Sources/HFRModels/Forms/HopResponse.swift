import Foundation

/// Classification of the page HFR answers after a write (HTTP 200 even on rejection).
public struct HopResponse: Sendable, Hashable, Codable {
    /// What the page says happened.
    public enum Kind: String, Sendable, Codable {
        /// A refresh redirect, or a `.hop` block without link or input.
        case success
        /// A `.hop` block with a link or input (flood, invalid token...); `message` explains.
        case rejected
        /// The session is not logged in.
        case loggedOut
        /// Moderator alert page: the message was already reported.
        case alreadyAlerted
        /// Matches no known shape; callers must not report success.
        case unrecognized
    }

    /// The classification.
    public var kind: Kind
    /// Text of the `.hop` block, tags removed and entities decoded.
    public var message: String?
    /// Target of the meta refresh, resolved against the request URL.
    public var refreshURL: URL?
    /// Fragment of the refresh URL, without the leading `#`.
    public var refreshAnchor: String?

    /// Creates a response description.
    public init(kind: Kind, message: String? = nil, refreshURL: URL? = nil, refreshAnchor: String? = nil) {
        self.kind = kind
        self.message = message
        self.refreshURL = refreshURL
        self.refreshAnchor = refreshAnchor
    }
}
