import Foundation
import HFRParsing

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

    /// Where `refreshURL` leads (LOT-095 router): a topic list after a new topic (`W40`, HFR names no topic id) or a
    /// whole-topic delete (`W19`, `W49`); the topic itself after a reply, an edit or the delete of a later post.
    public var refreshRoute: HFRLinkRoute {
        HFRLinkRoute.route(for: refreshURL)
    }

    /// True when HFR's answer to a delete says the whole topic went: it refreshes to a topic list (`W19` private,
    /// `W49` public, after which the topic is a 404, `R92`) instead of the topic (`W16a`, `W32`).
    public var deletedWholeTopic: Bool {
        guard action == .delete else { return false }
        switch refreshRoute {
        case .topicList, .privateMessageList: return true
        default: return false
        }
    }
}
