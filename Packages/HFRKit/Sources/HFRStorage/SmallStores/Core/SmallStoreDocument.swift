/// A versioned JSON document persisted by one of the small stores (LOT-064).
public protocol SmallStoreDocument: Sendable, Hashable, Codable {
    /// Format version written by this code. A larger version on disk is never overwritten.
    static var currentVersion: Int { get }
    /// The document a store starts from when nothing is stored yet.
    static var empty: Self { get }
    /// Format version of this document.
    var version: Int { get }
}
