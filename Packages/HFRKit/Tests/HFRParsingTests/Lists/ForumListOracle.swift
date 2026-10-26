import Foundation

/// The LOT-002 oracle output for a home page capture (kind `forums`): what the legacy parser returned and wrote.
struct ForumListOracle: Decodable {
    /// A legacy `Forum`: `aID` is always `""` for this parser; `subCats` repeats the parent first, then the sub-forums.
    struct Forum: Decodable {
        let aTitle: String
        let aURL: String
        let aID: String
        let subCats: [Forum]?
    }

    /// Input file as the exporter recorded it.
    struct Input: Decodable {
        let file: String
        let bytes: Int
    }

    /// Legacy writes outside the return value.
    struct SideEffects: Decodable {
        let hashCheck: String?
        let nbMP: Int?
    }

    let kind: String
    let exception: String?
    let input: Input
    let result: [Forum]?
    let sideEffects: SideEffects

    /// Loads `Fixtures/LOT-002/<name>.oracle.json`.
    static func load(_ name: String) throws -> ForumListOracle {
        let text = try Fixture.text("\(name).oracle", extension: "json", subdirectory: "Fixtures/LOT-002")
        return try JSONDecoder().decode(ForumListOracle.self, from: Data(text.utf8))
    }
}
