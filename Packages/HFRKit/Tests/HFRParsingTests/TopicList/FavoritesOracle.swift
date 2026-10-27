import Foundation

/// A LOT-002 oracle file for the legacy favourites parser (`schema` 1, kind `favorites`;
/// `docs/lots/LOT-002-list-oracle.md`). Session side effects the port does not return as such (category order
/// preferences, notifications) are not decoded.
struct FavoritesOracle: Decodable {
    let schema: Int
    let kind: String
    let input: Input
    let exception: String?
    let result: Result?
    let sideEffects: SideEffects

    struct Input: Decodable {
        let file: String
    }

    struct Result: Decodable {
        let favorites: [Section]
        let topicsSortedByLastPostDesc: [SortedTopic]
    }

    struct Section: Decodable {
        let forum: Forum
        let order: Int
        /// Same row shape as the topic list oracle, so its decoding is shared.
        let topics: [TopicListOracle.Topic]
    }

    struct Forum: Decodable {
        let aID: String
        let aTitle: String
        let aURL: String
    }

    struct SortedTopic: Decodable {
        let catID: Int
        let postID: Int
    }

    struct SideEffects: Decodable {
        let nbMP: Int?
        let hashCheck: String?
    }

    /// Loads `Fixtures/LOT-002/<case>.oracle.json`.
    static func load(_ name: String) throws -> FavoritesOracle {
        let json = try Fixture.text("\(name).oracle", extension: "json", subdirectory: "Fixtures/LOT-002")
        return try JSONDecoder().decode(FavoritesOracle.self, from: Data(json.utf8))
    }

    /// The captured page the oracle was computed on (its `input.file` is `../captures/<name>.html`).
    func capture() throws -> String {
        let name = URL(fileURLWithPath: input.file).deletingPathExtension().lastPathComponent
        return try Fixture.capture(name)
    }
}
