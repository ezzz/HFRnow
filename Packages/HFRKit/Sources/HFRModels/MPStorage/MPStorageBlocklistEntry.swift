import Foundation

/// A blocked pseudo in the synced MPStorage document (wire namespace `blacklist`: `{"createDate":ms,"username":s}`).
public struct MPStorageBlocklistEntry: Sendable, Hashable, Codable {
    /// Blacklisted pseudo, as written (the merge matches it case-insensitively; display matching rules are LOT-061).
    public var username: String
    /// When the entry was added.
    public var createdAt: Date?
    /// Keys written by other clients, kept so a rewrite does not drop them.
    public var extra: [String: JSONValue]

    private static let knownKeys: Set<String> = ["username", "createDate"]

    /// Creates an entry.
    public init(username: String, createdAt: Date? = nil, extra: [String: JSONValue] = [:]) {
        self.username = username
        self.createdAt = createdAt
        self.extra = extra
    }

    /// Decodes an entry; `username` is required.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        guard let username = try container.decodeLenientStringIfPresent(forKey: DynamicKey("username")) else {
            throw DecodingError.keyNotFound(DynamicKey("username"), .init(codingPath: decoder.codingPath, debugDescription: "No username"))
        }
        self.username = username
        createdAt = try container.decodeMillisecondDateIfPresent(forKey: DynamicKey("createDate"))
        extra = try container.decodeRemainingKeys(excluding: Self.knownKeys)
    }

    /// Encodes with millisecond dates and the preserved keys.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        try container.encode(username, forKey: DynamicKey("username"))
        try container.encodeMilliseconds(createdAt, forKey: DynamicKey("createDate"))
        try container.encodeRemainingKeys(extra, excluding: Self.knownKeys)
    }
}
