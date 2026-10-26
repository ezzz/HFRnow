import Foundation

/// An item of a list section, as the mutations and the merge see it.
public protocol MPStorageItem: Sendable, Hashable, Codable {
    /// Identity used to match the same item across copies of the document and in tombstones.
    var storageKey: String { get }
    /// Creation date when the wire shape has one; compared with tombstone dates.
    var storageDate: Date? { get }
}

extension MPStorageBlocklistEntry: MPStorageItem {
    /// The pseudo lower-cased, as legacy compares it (`MPStorage.m:250, 293`).
    public var storageKey: String { username.lowercased() }
    /// `createDate`.
    public var storageDate: Date? { createdAt }
}

extension MPStorageBookmark: MPStorageItem {
    /// `cat-post-numreponse` (`numreponse` is unique per category only, E18).
    public var storageKey: String { id }
    /// `createDate`.
    public var storageDate: Date? { createdAt }
}

extension MPStorageMPFlag: MPStorageItem {
    /// The conversation number.
    public var storageKey: String { String(topic) }
    /// Flags carry no date in v0.1.
    public var storageDate: Date? { nil }
}
