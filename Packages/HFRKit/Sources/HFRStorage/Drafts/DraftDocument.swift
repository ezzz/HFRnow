import Foundation
import HFRModels

/// Everything the draft store persists.
///
/// The drafts are read entry by entry (#1183): an entry this build cannot read (a context of a newer build, a malformed date)
/// is left out and counted in `unreadableEntryCount`, and the store sets the file as it was aside before writing the readable
/// drafts back (`DraftStore`), so one entry never costs the others and nothing is deleted.
public struct DraftDocument: Sendable, Hashable, Codable {
    /// Format version written by this code.
    public static let currentVersion = 1

    /// Format version.
    public var version: Int
    /// Drafts, at most one per account and context.
    public var drafts: [Draft]
    /// Entries of the file read that this build could not read; never written (the file they came from is set aside).
    public var unreadableEntryCount: Int

    /// Creates a document.
    public init(version: Int = DraftDocument.currentVersion, drafts: [Draft] = [], unreadableEntryCount: Int = 0) {
        self.version = version
        self.drafts = drafts
        self.unreadableEntryCount = unreadableEntryCount
    }

    private enum CodingKeys: String, CodingKey {
        case version, drafts
    }

    /// One entry of `drafts`: the draft, or nil when this build cannot read it.
    private struct Entry: Decodable {
        let draft: Draft?

        init(from decoder: any Decoder) throws {
            draft = try? Draft(from: decoder)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        let entries = try container.decode([Entry].self, forKey: .drafts)
        drafts = entries.compactMap(\.draft)
        unreadableEntryCount = entries.count - drafts.count
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(drafts, forKey: .drafts)
    }
}
