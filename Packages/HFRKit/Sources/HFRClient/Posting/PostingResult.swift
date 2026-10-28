import Foundation

/// HFR's confirmation of a write.
public struct PostingResult: Sendable, Equatable {
    /// The write HFR confirmed.
    public var action: PostingAction
    /// HFR's sentence, for example "Votre réponse a été postée avec succès !".
    public var message: String
    /// The page HFR refreshes to (`…#bas` after a reply, `…#t<numreponse>` after an edit, the list after a new thread or
    /// a delete). Always `https` on `forum.hardware.fr` (LOT-037).
    public var refreshURL: URL
    /// Fragment of `refreshURL` without `#` (`bas`, `t<numreponse>`); nil when it has none (delete, new thread).
    public var refreshAnchor: String?
    /// `numreponse` of the edited or deleted message, read from its form; nil for the other writes.
    public var postNumber: Int?

    /// Creates a result.
    public init(action: PostingAction, message: String, refreshURL: URL, refreshAnchor: String? = nil, postNumber: Int? = nil) {
        self.action = action
        self.message = message
        self.refreshURL = refreshURL
        self.refreshAnchor = refreshAnchor
        self.postNumber = postNumber
    }
}
