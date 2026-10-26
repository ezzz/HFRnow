import Foundation
import Testing

/// A LOT-005 oracle (`Fixtures/LOT-005/<case>.oracle.json`, `docs/lots/LOT-005-small-parsers-oracle.md`): what the legacy
/// code produced on one capture, plus the capture itself.
struct Lot005Oracle {
    /// Case id such as `R53b`.
    let id: String
    /// Oracle kind (`search-redirect`, `profile-edit`, `smiley-search`, `smiley-keywords`, `poll`, `profile`).
    let kind: String
    /// Text of the captured page the legacy code read.
    let html: String
    /// `input.context`: the effective inputs of the legacy run.
    let context: [String: Any]
    /// `result`: the legacy output.
    let result: [String: Any]

    private static let subdirectory = "Fixtures/LOT-005"

    /// The oracle of a case id.
    static func load(_ id: String) throws -> Lot005Oracle {
        let root = try object(Fixture.text("\(id).oracle", extension: "json", subdirectory: subdirectory))
        let input = try #require(root["input"] as? [String: Any])
        let file = try #require(input["file"] as? String)
        let capture = file.split(separator: "/").last.map { String($0).replacing(".html", with: "") } ?? file
        return Lot005Oracle(
            id: id,
            kind: try #require(root["kind"] as? String),
            html: try Fixture.capture(capture),
            context: input["context"] as? [String: Any] ?? [:],
            result: try #require(root["result"] as? [String: Any])
        )
    }

    /// Case ids of `oracle-map.json` per kind (`R53b.html` becomes `R53b`).
    static func mappedCases(ofKinds kinds: Set<String>) throws -> Set<String> {
        let map = try object(Fixture.text("oracle-map", extension: "json", subdirectory: subdirectory))
        return Set(map.compactMap { key, value in
            guard let kind = (value as? [String: Any])?["kind"] as? String, kinds.contains(kind) else { return nil }
            return key.replacing(".html", with: "")
        })
    }

    private static func object(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
}
