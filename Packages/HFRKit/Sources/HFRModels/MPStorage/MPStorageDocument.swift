import Foundation

/// The JSON document HFR clients keep in a private message used as a database (audit E §2.6, E23).
/// `{"data":[{"version":"0.1", ...}],"sourceName":s,"lastUpdate":ms}`. Decoding never resets or drops what it
/// does not understand; mutation and conflict handling are HFRStorage's job.
public struct MPStorageDocument: Sendable, Hashable, Codable {
    /// Subject of the storage private message.
    public static let subject = "a2bcc09b796b8c6fab77058ff8446c34"
    /// Recipient of the storage private message.
    public static let recipient = "MultiMP"
    /// Schema version this app writes.
    public static let schemaVersion = "0.1"

    /// Versioned entries; today a single one.
    public var data: [MPStorageEntry]
    /// Last writer of the document.
    public var sourceName: String?
    /// Last write instant of the document.
    public var lastUpdate: Date?
    /// Other root keys, kept verbatim.
    public var extra: [String: JSONValue]

    private static let knownKeys: Set<String> = ["data", "sourceName", "lastUpdate"]

    /// Creates a document; the default is a new empty document with one entry.
    public init(
        data: [MPStorageEntry] = [MPStorageEntry()],
        sourceName: String? = nil,
        lastUpdate: Date? = nil,
        extra: [String: JSONValue] = [:]
    ) {
        self.data = data
        self.sourceName = sourceName
        self.lastUpdate = lastUpdate
        self.extra = extra
    }

    /// Decodes a document; `data` is required.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        data = try container.decode([MPStorageEntry].self, forKey: DynamicKey("data"))
        sourceName = try container.decodeLenientStringIfPresent(forKey: DynamicKey("sourceName"))
        lastUpdate = try container.decodeMillisecondDateIfPresent(forKey: DynamicKey("lastUpdate"))
        extra = try container.decodeRemainingKeys(excluding: Self.knownKeys)
    }

    /// Encodes the document.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        try container.encode(data, forKey: DynamicKey("data"))
        try container.encodeIfPresent(sourceName, forKey: DynamicKey("sourceName"))
        try container.encodeMilliseconds(lastUpdate, forKey: DynamicKey("lastUpdate"))
        try container.encodeRemainingKeys(extra, excluding: Self.knownKeys)
    }
}
