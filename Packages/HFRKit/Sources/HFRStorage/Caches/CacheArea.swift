/// A named part of the cache directory. Each area has its own folder and its own eviction policy.
public enum CacheArea: String, Sendable, CaseIterable {
    /// Avatar image files, keyed by pseudo. Same folder name as the legacy app (`Caches/cache/avatars`).
    case avatars
    /// Rendered topic pages written for a web view, and other short-lived files.
    case topicPages = "pages"
    /// Topic pages saved for reading without network (LOT-068, `OfflineTopicStore`).
    case offlineTopics = "offline"

    /// The eviction policy applied at launch.
    public var evictionPolicy: CacheEvictionPolicy {
        switch self {
        case .avatars: .avatars
        case .topicPages: .topicPages
        case .offlineTopics: .offlineTopics
        }
    }
}
