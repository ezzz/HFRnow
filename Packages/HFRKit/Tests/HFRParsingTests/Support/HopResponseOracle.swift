import Foundation
import Testing

/// The `response` oracle of one capture (`Fixtures/LOT-004/<case>.oracle.json`, LOT-004): what the legacy classifier said.
struct HopResponseOracle {
    /// Case id such as `W10`.
    let id: String
    /// Text of the captured page the legacy code read.
    let html: String
    /// `input.context.flow`: `reply` or `delete`.
    let flow: String
    /// `result.legacy`: the legacy classification, message and anchor.
    let legacy: [String: Any]

    /// The oracle of a case id.
    static func load(_ id: String) throws -> HopResponseOracle {
        let text = try Fixture.text("\(id).oracle", extension: "json", subdirectory: "Fixtures/LOT-004")
        let root = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(root["kind"] as? String == "response")
        let input = try #require(root["input"] as? [String: Any])
        let context = try #require(input["context"] as? [String: Any])
        let file = try #require(input["file"] as? String)
        let capture = file.split(separator: "/").last.map { String($0).replacing(".html", with: "") } ?? file
        let result = try #require(root["result"] as? [String: Any])
        return HopResponseOracle(
            id: id,
            html: try Fixture.capture(capture),
            flow: try #require(context["flow"] as? String),
            legacy: try #require(result["legacy"] as? [String: Any])
        )
    }
}
