import Foundation

/// A read position of a conversation in the MPStorage document (`{"post":n,"p":s,"href":s,"page":n,"uri":s}`);
/// DTCloud-style clients use it as a position marker, not as a read/unread flag.
public struct MPStorageMPFlag: Sendable, Hashable, Identifiable, Codable {
    /// Stable identity: the conversation number.
    public var id: Int { topic }
    /// Conversation (topic) number, the wire key `post`.
    public var topic: Int
    /// The wire key `p`, kept as written.
    public var pValue: String?
    /// Link to the position.
    public var href: String?
    /// Page of the position.
    public var page: Int?
    /// The wire key `uri`.
    public var uri: String?
    /// Keys written by other clients, kept so a rewrite does not drop them.
    public var extra: [String: JSONValue]

    private static let knownKeys: Set<String> = ["post", "p", "href", "page", "uri"]

    /// Creates a flag.
    public init(
        topic: Int,
        pValue: String? = nil,
        href: String? = nil,
        page: Int? = nil,
        uri: String? = nil,
        extra: [String: JSONValue] = [:]
    ) {
        self.topic = topic
        self.pValue = pValue
        self.href = href
        self.page = page
        self.uri = uri
        self.extra = extra
    }

    /// Decodes a flag; `post` is required and may be a number or a string.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        topic = try container.decodeLenientInt(forKey: DynamicKey("post"))
        pValue = try container.decodeLenientStringIfPresent(forKey: DynamicKey("p"))
        href = try container.decodeLenientStringIfPresent(forKey: DynamicKey("href"))
        page = try container.decodeLenientIntIfPresent(forKey: DynamicKey("page"))
        uri = try container.decodeLenientStringIfPresent(forKey: DynamicKey("uri"))
        extra = try container.decodeRemainingKeys(excluding: Self.knownKeys)
    }

    /// Encodes `post` and `page` as numbers, the other keys as strings.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        try container.encode(topic, forKey: DynamicKey("post"))
        try container.encodeIfPresent(pValue, forKey: DynamicKey("p"))
        try container.encodeIfPresent(href, forKey: DynamicKey("href"))
        try container.encodeIfPresent(page, forKey: DynamicKey("page"))
        try container.encodeIfPresent(uri, forKey: DynamicKey("uri"))
        try container.encodeRemainingKeys(extra, excluding: Self.knownKeys)
    }
}
