import Foundation

/// An item of a list section, as the mutations and the merge see it.
public protocol MPStorageItem: Sendable, Hashable, Codable {
    /// Identity used to match the same item across copies of the document and in tombstones.
    var storageKey: String { get }
    /// Creation date when the wire shape has one; compared with tombstone dates.
    var storageDate: Date? { get }
    /// The copy a merge keeps when both sides changed the item differently, or nil for the default rule.
    static func conflictWinner(mine: Self, other: Self) -> Self?
}

extension MPStorageItem {
    /// No rule of its own: the merge's default applies.
    public static func conflictWinner(mine: Self, other: Self) -> Self? { nil }
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

    /// The further position (page, then message; nil on a tie, so the merge's default rule applies): a read position only
    /// moves forward (legacy `pageToSave >= currentStoredPage`, `MessagesView.swift:3589-3590` @ 87fe0d1c), so a flag another
    /// client moved further is never taken back by an earlier page read here with a stale copy (#858).
    public static func conflictWinner(mine: MPStorageMPFlag, other: MPStorageMPFlag) -> MPStorageMPFlag? {
        let theirs = (other.page ?? -1, other.messageNumber ?? 0), ours = (mine.page ?? -1, mine.messageNumber ?? 0)
        if theirs == ours { return nil }
        return theirs > ours ? other : mine
    }
}
