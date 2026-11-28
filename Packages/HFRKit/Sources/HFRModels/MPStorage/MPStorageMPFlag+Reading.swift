import Foundation

/// The read position a group conversation's reader writes (#858), in legacy's shape (`MessagesView.swift:3582-3606` @ 87fe0d1c).
extension MPStorageMPFlag {
    /// The flag of conversation `conversation` at `lastMessage`, the last message of page `page`: `href` is its `t<numreponse>`
    /// anchor (`normalizedMessageAnchor`, `:3613-3623`), `p` the conversation link's (`"1"` when it has none, `:3592`), and
    /// `uri` the conversation's page link (`:3594`).
    public init(conversation: Int, page: Int, lastMessage: Int, pValue: String?) {
        let pageValue = pValue.flatMap { $0.isEmpty ? nil : $0 } ?? "1"
        let uri = "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=prive&post=\(conversation)&page=\(page)&p=\(pageValue)"
            + "&sondage=0&owntopic=0&trash=0&trash_post=0&print=0&numreponse=0&quote_only=0&new=0&nojs=0#t\(lastMessage)"
        self.init(topic: conversation, pValue: pageValue, href: "t\(lastMessage)", page: page, uri: uri)
    }

    /// The message the flag stands on: the number of its `t<numreponse>` anchor; nil for any other `href`.
    public var messageNumber: Int? {
        guard let href, href.first == "t", let number = Int(href.dropFirst()), number > 0 else { return nil }
        return number
    }
}

extension MPStorageDocument {
    /// Moves a conversation's read position to `flag` when its page is at least the stored one (legacy
    /// `pageToSave >= currentStoredPage`, `MessagesView.swift:3589-3590` @ 87fe0d1c; a stored flag without a page reads as -1,
    /// `MPStorage.m:547-563`). Keys another client added to the stored flag are kept. False when it would move back or nothing
    /// changes.
    @discardableResult
    public mutating func moveMPFlag(_ flag: MPStorageMPFlag, stamp: MPStorageStamp) throws -> Bool {
        let stored = writableEntryIndex.flatMap { data[$0].mpFlags?.list.first { $0.topic == flag.topic } }
        if let stored, (flag.page ?? 0) < (stored.page ?? -1) { return false }
        var moved = flag
        moved.extra = stored?.extra ?? flag.extra
        return try upsertMPFlag(moved, stamp: stamp)
    }
}
