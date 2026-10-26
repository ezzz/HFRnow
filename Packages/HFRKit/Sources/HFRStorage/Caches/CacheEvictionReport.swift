/// What an eviction pass did.
public struct CacheEvictionReport: Sendable, Equatable {
    /// Files removed.
    public var removedFileCount = 0
    /// Bytes freed.
    public var removedBytes = 0
    /// Bytes still cached.
    public var remainingBytes = 0
    /// Paths that could not be listed or removed, with the reason; the pass continues past them.
    public var failures: [String] = []

    /// Creates an empty report.
    public init() {}
}
