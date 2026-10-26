import Foundation

/// One namespace of the document (`blacklist`, `mpFlags`, `bookmarks`): a list plus writer metadata.
public struct MPStorageSection<Item: Sendable & Hashable & Codable>: Sendable, Hashable, Codable {
    /// Items that decoded.
    public var list: [Item]
    /// Raw items that did not decode; written back after `list` so a malformed entry is never destroyed.
    public var undecodableItems: [JSONValue]
    /// Last writer of this section.
    public var sourceName: String?
    /// Last write instant of this section.
    public var lastUpdate: Date?
    /// Dated deletions (wire key `tombstones`, an addition readers ignore); see `MPStorageTombstone`.
    public var tombstones: [MPStorageTombstone]
    /// Other keys (e.g. `active` on `mpFlags`), kept verbatim. A `tombstones` key that is not an array of
    /// tombstones belongs to another client: it stays here and this section then records no tombstones.
    public var extra: [String: JSONValue]

    /// Whether `tombstones` can be written: false when another client uses the key for something else.
    public var canRecordTombstones: Bool { extra[Self.tombstonesKey] == nil }

    static var tombstonesKey: String { "tombstones" }

    private static var knownKeys: Set<String> { ["list", "sourceName", "lastUpdate"] }

    /// Creates a section.
    public init(
        list: [Item] = [],
        undecodableItems: [JSONValue] = [],
        sourceName: String? = nil,
        lastUpdate: Date? = nil,
        tombstones: [MPStorageTombstone] = [],
        extra: [String: JSONValue] = [:]
    ) {
        self.list = list
        self.undecodableItems = undecodableItems
        self.sourceName = sourceName
        self.lastUpdate = lastUpdate
        self.tombstones = tombstones
        self.extra = extra
    }

    /// Wraps an element so one bad item cannot fail the whole list.
    private struct Lossy: Decodable {
        let item: Item?
        let raw: JSONValue

        init(from decoder: any Decoder) throws {
            raw = try JSONValue(from: decoder)
            item = try? Item(from: decoder)
        }
    }

    /// Decodes a section; an absent `list` (the real documents contain `{}`) is an empty list.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var items: [Item] = []
        var rejected: [JSONValue] = []
        if container.contains(DynamicKey("list")), try !container.decodeNil(forKey: DynamicKey("list")) {
            for element in try container.decode([Lossy].self, forKey: DynamicKey("list")) {
                if let item = element.item { items.append(item) } else { rejected.append(element.raw) }
            }
        }
        list = items
        undecodableItems = rejected
        sourceName = try container.decodeLenientStringIfPresent(forKey: DynamicKey("sourceName"))
        lastUpdate = try container.decodeMillisecondDateIfPresent(forKey: DynamicKey("lastUpdate"))
        var remaining = try container.decodeRemainingKeys(excluding: Self.knownKeys)
        let tombstonesKey = DynamicKey(Self.tombstonesKey)
        if container.contains(tombstonesKey),
           let decoded = try? container.decode([MPStorageTombstone].self, forKey: tombstonesKey) {
            tombstones = decoded
            remaining[Self.tombstonesKey] = nil
        } else {
            tombstones = []
        }
        extra = remaining
    }

    /// Encodes `list` (always present) followed by the undecodable items; `tombstones` only when there are some.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        var unkeyed = container.nestedUnkeyedContainer(forKey: DynamicKey("list"))
        for item in list { try unkeyed.encode(item) }
        for raw in undecodableItems { try unkeyed.encode(raw) }
        try container.encodeIfPresent(sourceName, forKey: DynamicKey("sourceName"))
        try container.encodeMilliseconds(lastUpdate, forKey: DynamicKey("lastUpdate"))
        try container.encodeRemainingKeys(extra, excluding: Self.knownKeys)
        if !tombstones.isEmpty, canRecordTombstones {
            try container.encode(tombstones, forKey: DynamicKey(Self.tombstonesKey))
        }
    }
}
