import Foundation

/// A bookmarked message in the MPStorage document
/// (`{"createDate":ms,"post":s,"author":s,"numreponse":n,"cat":s,"label":s}`).
public struct MPStorageBookmark: Sendable, Hashable, Identifiable, Codable {
    /// Stable identity: category, topic and message number (`numreponse` is only unique per category).
    public var id: String { "\(category)-\(topic)-\(numreponse)" }
    /// Topic number, the wire key `post`.
    public var topic: Int
    /// Category as written (`cat`), a string on the wire.
    public var category: String
    /// Message number inside the category.
    public var numreponse: Int
    /// Author of the bookmarked message.
    public var author: String
    /// User label.
    public var label: String
    /// When the bookmark was created.
    public var createdAt: Date?
    /// Keys written by other clients, kept so a rewrite does not drop them.
    public var extra: [String: JSONValue]

    private static let knownKeys: Set<String> = ["post", "cat", "numreponse", "author", "label", "createDate"]

    /// Creates a bookmark.
    public init(
        topic: Int,
        category: String,
        numreponse: Int,
        author: String,
        label: String,
        createdAt: Date? = nil,
        extra: [String: JSONValue] = [:]
    ) {
        self.topic = topic
        self.category = category
        self.numreponse = numreponse
        self.author = author
        self.label = label
        self.createdAt = createdAt
        self.extra = extra
    }

    /// Decodes a bookmark; `post`, `cat` and `numreponse` are required, numbers or numeric strings.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        topic = try container.decodeLenientInt(forKey: DynamicKey("post"))
        numreponse = try container.decodeLenientInt(forKey: DynamicKey("numreponse"))
        guard let category = try container.decodeLenientStringIfPresent(forKey: DynamicKey("cat")) else {
            throw DecodingError.keyNotFound(DynamicKey("cat"), .init(codingPath: decoder.codingPath, debugDescription: "No cat"))
        }
        self.category = category
        author = try container.decodeLenientStringIfPresent(forKey: DynamicKey("author")) ?? ""
        label = try container.decodeLenientStringIfPresent(forKey: DynamicKey("label")) ?? ""
        createdAt = try container.decodeMillisecondDateIfPresent(forKey: DynamicKey("createDate"))
        extra = try container.decodeRemainingKeys(excluding: Self.knownKeys)
    }

    /// Encodes in the legacy shape: `post` and `cat` as strings, `numreponse` as a number.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        try container.encode(String(topic), forKey: DynamicKey("post"))
        try container.encode(category, forKey: DynamicKey("cat"))
        try container.encode(numreponse, forKey: DynamicKey("numreponse"))
        try container.encode(author, forKey: DynamicKey("author"))
        try container.encode(label, forKey: DynamicKey("label"))
        try container.encodeMilliseconds(createdAt, forKey: DynamicKey("createDate"))
        try container.encodeRemainingKeys(extra, excluding: Self.knownKeys)
    }
}
