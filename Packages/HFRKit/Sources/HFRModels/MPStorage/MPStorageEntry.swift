import Foundation

/// One versioned entry of the document's `data` array.
public struct MPStorageEntry: Sendable, Hashable, Codable {
    /// Schema version, `0.1` today; nil when absent. A version this app does not know must not be rewritten blindly.
    public var version: String?
    /// Synced blocklist (wire key `blacklist`).
    public var blocklist: MPStorageSection<MPStorageBlocklistEntry>?
    /// Conversation read positions.
    public var mpFlags: MPStorageSection<MPStorageMPFlag>?
    /// Bookmarks.
    public var bookmarks: MPStorageSection<MPStorageBookmark>?
    /// Last writer of the entry.
    public var sourceName: String?
    /// Last write instant of the entry.
    public var lastUpdate: Date?
    /// Namespaces of other clients (`hfrChat`, `superFavs`, ...), kept verbatim.
    public var extra: [String: JSONValue]

    private static let knownKeys: Set<String> = ["version", "blacklist", "mpFlags", "bookmarks", "sourceName", "lastUpdate"]

    /// Creates an entry.
    public init(
        version: String? = MPStorageDocument.schemaVersion,
        blocklist: MPStorageSection<MPStorageBlocklistEntry>? = nil,
        mpFlags: MPStorageSection<MPStorageMPFlag>? = nil,
        bookmarks: MPStorageSection<MPStorageBookmark>? = nil,
        sourceName: String? = nil,
        lastUpdate: Date? = nil,
        extra: [String: JSONValue] = [:]
    ) {
        self.version = version
        self.blocklist = blocklist
        self.mpFlags = mpFlags
        self.bookmarks = bookmarks
        self.sourceName = sourceName
        self.lastUpdate = lastUpdate
        self.extra = extra
    }

    /// Decodes an entry, keeping unknown namespaces.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        version = try container.decodeLenientStringIfPresent(forKey: DynamicKey("version"))
        blocklist = try container.decodeIfPresent(MPStorageSection<MPStorageBlocklistEntry>.self, forKey: DynamicKey("blacklist"))
        mpFlags = try container.decodeIfPresent(MPStorageSection<MPStorageMPFlag>.self, forKey: DynamicKey("mpFlags"))
        bookmarks = try container.decodeIfPresent(MPStorageSection<MPStorageBookmark>.self, forKey: DynamicKey("bookmarks"))
        sourceName = try container.decodeLenientStringIfPresent(forKey: DynamicKey("sourceName"))
        lastUpdate = try container.decodeMillisecondDateIfPresent(forKey: DynamicKey("lastUpdate"))
        extra = try container.decodeRemainingKeys(excluding: Self.knownKeys)
    }

    /// Encodes the entry with its preserved namespaces.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        try container.encodeIfPresent(version, forKey: DynamicKey("version"))
        try container.encodeIfPresent(blocklist, forKey: DynamicKey("blacklist"))
        try container.encodeIfPresent(mpFlags, forKey: DynamicKey("mpFlags"))
        try container.encodeIfPresent(bookmarks, forKey: DynamicKey("bookmarks"))
        try container.encodeIfPresent(sourceName, forKey: DynamicKey("sourceName"))
        try container.encodeMilliseconds(lastUpdate, forKey: DynamicKey("lastUpdate"))
        try container.encodeRemainingKeys(extra, excluding: Self.knownKeys)
    }
}
