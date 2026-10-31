import Foundation
import HFRModels

/// The on-disk form of an `OfflinePage`: one JSON file per page, version first.
struct OfflinePageRecord: Codable {
    var version: Int
    var category: Int
    var topic: Int
    var page: Int
    var title: String
    var html: String
    var savedAt: Date

    /// Sorted keys; dates in the default strategy, which round-trips a `Date` exactly (seconds since 1970 does not).
    static func encode(_ record: Self) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(record)
    }

    /// Only the version, read first so that a file of another format is reported as such, whatever its other fields.
    private struct VersionProbe: Decodable {
        var version: Int
    }

    init(_ page: OfflinePage) {
        let category = if case .forum(let number) = page.topic.category { number } else { 0 }
        self.init(
            version: OfflineTopicStore.currentVersion, category: category, topic: page.topic.topic, page: page.page,
            title: page.title, html: page.html, savedAt: page.savedAt
        )
    }

    init(version: Int, category: Int, topic: Int, page: Int, title: String, html: String, savedAt: Date) {
        self.version = version
        self.category = category
        self.topic = topic
        self.page = page
        self.title = title
        self.html = html
        self.savedAt = savedAt
    }

    /// The page in `data`: `unsupportedVersion` for another format version (older or newer: version 1 is the first),
    /// `unreadable` for anything that is not a well-formed version-1 page.
    static func decode(_ data: Data) throws(OfflineStoreError) -> OfflinePage {
        let decoder = JSONDecoder()
        guard let probe = try? decoder.decode(VersionProbe.self, from: data) else { throw .unreadable }
        guard probe.version == OfflineTopicStore.currentVersion else { throw .unsupportedVersion(probe.version) }
        guard let record = try? decoder.decode(Self.self, from: data), record.category > 0, record.topic > 0, record.page >= 1
        else { throw .unreadable }
        return OfflinePage(
            topic: TopicID(category: .forum(record.category), topic: record.topic), page: record.page,
            title: record.title, html: record.html, savedAt: record.savedAt
        )
    }

    /// True when a `hash_check` input of `html` has a value: the page was served to a logged-in session (`R21`, `R32b`),
    /// while every input is empty on a page served without cookies (`R20`, `R22a`, `R28`). An input whose value cannot
    /// be read counts as holding one (fail closed).
    static func holdsSessionToken(_ html: String) -> Bool {
        for tag in html.matches(of: /<input\b[^>]*>/.ignoresCase()) {
            let input = tag.output
            guard input.firstMatch(of: /\bname\s*=\s*["']?hash_check\b/.ignoresCase()) != nil else { continue }
            guard let value = input.firstMatch(of: /\bvalue\s*=\s*(?:"([^"]*)"|'([^']*)')/.ignoresCase()) else { return true }
            if !(value.output.1 ?? value.output.2 ?? "").isEmpty { return true }
        }
        return false
    }
}
