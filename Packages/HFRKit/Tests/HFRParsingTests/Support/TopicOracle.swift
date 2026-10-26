import Foundation

/// The LOT-003 oracle of a topic page (`Fixtures/LOT-003/<case>.oracle.json`), reduced to the message-level fields
/// of the legacy `LinkItem` that LOT-030 reproduces, plus the avatar requests the pipeline made.
struct TopicOracle: Decodable {
    /// A legacy `LinkItem` as exported (`docs/lots/LOT-003-topic-oracle.md`, `result.messages[]`).
    struct Message: Decodable {
        var index: Int
        var postID: String?
        var name: String?
        var isDel: Bool
        var messageDate: String?
        var dicoHTML: String?
        var imageUI: String?
        var quotedNB: String?
        var quotedLINK: String?
        var editedTime: String?
        var urlQuoteDecoded: String?
    }

    struct Result: Decodable {
        var messages: [Message]
    }

    struct SideEffects: Decodable {
        var networkRequests: [String]
    }

    /// One entry of `oracle-map.json`.
    struct MapEntry: Decodable {
        var kind: String
        var path: String
        var currentURL: String?
    }

    var exception: String?
    var result: Result
    var sideEffects: SideEffects

    /// Fixtures subdirectory holding the topic oracles.
    static let subdirectory = "Fixtures/LOT-003"

    /// The oracle of a case id such as `R20`.
    static func load(_ caseID: String) throws -> TopicOracle {
        let json = try Fixture.text("\(caseID).oracle", extension: "json", subdirectory: subdirectory)
        return try JSONDecoder().decode(TopicOracle.self, from: Data(json.utf8))
    }

    /// The oracle map, keyed by case id (`R20.html` → `R20`).
    static func loadMap() throws -> [String: MapEntry] {
        let json = try Fixture.text("oracle-map", extension: "json", subdirectory: subdirectory)
        let raw = try JSONDecoder().decode([String: MapEntry].self, from: Data(json.utf8))
        return Dictionary(uniqueKeysWithValues: raw.map { key, entry in
            (key.hasSuffix(".html") ? String(key.dropLast(5)) : key, entry)
        })
    }

    /// The capture of a map entry (`../captures/R20-topic-p1-anon.html` → `R20-topic-p1-anon`).
    static func capture(for entry: MapEntry) throws -> String {
        let name = entry.path.split(separator: "/").last.map(String.init) ?? entry.path
        return try Fixture.capture(name.hasSuffix(".html") ? String(name.dropLast(5)) : name)
    }
}
