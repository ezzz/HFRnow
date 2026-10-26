/// A named part of the cache directory. Each area has its own folder and its own eviction policy.
public enum CacheArea: String, Sendable, CaseIterable {
    /// Avatar image files, keyed by pseudo. Same folder name as the legacy app (`Caches/cache/avatars`).
    case avatars
    /// Rendered topic pages written for a web view, and other short-lived files.
    case topicPages = "pages"

    /// The eviction policy applied at launch.
    public var evictionPolicy: CacheEvictionPolicy {
        switch self {
        case .avatars: .avatars
        case .topicPages: .topicPages
        }
    }
}
