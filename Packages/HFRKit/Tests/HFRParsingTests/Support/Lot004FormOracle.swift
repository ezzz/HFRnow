import Foundation
import Testing

/// A LOT-004 `form` oracle (`Fixtures/LOT-004/<case>.oracle.json`, `docs/lots/LOT-004-forms-storage-oracle.md`): what the
/// legacy composer code extracted from one capture, plus the capture itself.
struct Lot004FormOracle {
    /// Case id such as `R41a`.
    let id: String
    /// Text of the captured page the legacy code read.
    let html: String
    /// `result.legacy`: the legacy extraction (`formAction`, `inputData`, `loopOrder`, `contentForm`, `subcats`, `smileys`…).
    let legacy: [String: Any]

    private static let subdirectory = "Fixtures/LOT-004"

    /// The oracle of a case id.
    static func load(_ id: String) throws -> Lot004FormOracle {
        let root = try object(Fixture.text("\(id).oracle", extension: "json", subdirectory: subdirectory))
        #expect(root["kind"] as? String == "form")
        let input = try #require(root["input"] as? [String: Any])
        let file = try #require(input["file"] as? String)
        let capture = file.split(separator: "/").last.map { String($0).replacing(".html", with: "") } ?? file
        let result = try #require(root["result"] as? [String: Any])
        return Lot004FormOracle(id: id, html: try Fixture.capture(capture), legacy: try #require(result["legacy"] as? [String: Any]))
    }

    /// Case ids of `oracle-map.json` whose kind is `form`.
    static func mappedFormCases() throws -> Set<String> {
        let map = try object(Fixture.text("oracle-map", extension: "json", subdirectory: subdirectory))
        return Set(map.compactMap { key, value in
            (value as? [String: Any])?["kind"] as? String == "form" ? key.replacing(".html", with: "") : nil
        })
    }

    private static func object(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
}
