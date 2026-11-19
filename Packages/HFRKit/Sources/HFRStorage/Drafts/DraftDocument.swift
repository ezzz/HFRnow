import Foundation
import HFRModels

/// Everything the draft store persists.
///
/// The drafts are read entry by entry (#1183): an entry this build cannot read (a context of a newer build, a malformed date)
/// sets that entry aside, not the file. It is kept as written in `unreadableDrafts` and written back after the readable
/// drafts on every save, so a newer build still finds it; it is never shown, expired or counted here.
public struct DraftDocument: Sendable, Hashable, Codable {
    /// Format version written by this code.
    public static let currentVersion = 1

    /// Format version.
    public var version: Int
    /// Drafts, at most one per account and context.
    public var drafts: [Draft]
    /// Entries of `drafts` this build could not read, as they were written.
    public var unreadableDrafts: [JSONValue]

    /// Creates a document.
    public init(version: Int = DraftDocument.currentVersion, drafts: [Draft] = [], unreadableDrafts: [JSONValue] = []) {
        self.version = version
        self.drafts = drafts
        self.unreadableDrafts = unreadableDrafts
    }

    private enum CodingKeys: String, CodingKey {
        case version, drafts
    }

    /// One entry of `drafts`: the draft when this build reads it, and the entry as written in any case.
    private struct Entry: Decodable {
        let draft: Draft?
        let raw: JSONValue

        init(from decoder: any Decoder) throws {
            raw = try JSONValue(from: decoder)
            draft = try? Draft(from: decoder)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        let entries = try container.decode([Entry].self, forKey: .drafts)
        drafts = entries.compactMap(\.draft)
        unreadableDrafts = entries.filter { $0.draft == nil }.map(\.raw)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        var list = container.nestedUnkeyedContainer(forKey: .drafts)
        for draft in drafts { try list.encode(draft) }
        for entry in unreadableDrafts { try list.encode(entry) }
    }
}
