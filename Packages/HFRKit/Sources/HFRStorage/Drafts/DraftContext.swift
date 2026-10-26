import HFRModels

/// What a draft is written for. Each context has its own draft, so writing a quote, an edit or a private message
/// never touches the reply draft of a topic (the legacy app had a single global draft, audit D §4).
public enum DraftContext: Sendable, Hashable, Codable {
    /// A reply in a topic, written while reading `page` (1-based).
    case reply(topic: TopicID, page: Int)
    /// A new topic in a forum category.
    case newTopic(forum: CategoryID)
    /// A new private message to a recipient (case and zero-width spaces ignored, like blocklist matching).
    case privateMessage(recipient: String)
    /// The edit of an existing message (`numreponse`) of a topic.
    case edit(topic: TopicID, post: Int)
    /// The single global draft of the legacy app (`composerDraftText` / `brouillon`), kept by the legacy import (LOT-067).
    case legacyGlobal

    /// A stable identity string: two contexts designate the same draft exactly when their keys are equal.
    public var storageKey: String {
        switch self {
        case .reply(let topic, let page):
            "reply:\(topic.category.queryValue):\(topic.topic):\(page)"
        case .newTopic(let forum):
            "newtopic:\(forum.queryValue)"
        case .privateMessage(let recipient):
            "mp:\(DraftNameNormalizer.normalize(recipient))"
        case .edit(let topic, let post):
            "edit:\(topic.category.queryValue):\(topic.topic):\(post)"
        case .legacyGlobal:
            "legacy"
        }
    }
}
