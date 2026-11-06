import Foundation
import Testing

/// A LOT-004 `form` oracle (`Fixtures/LOT-004/<case>.oracle.json`, `docs/lots/LOT-004-forms-storage-oracle.md`): what the
/// legacy composer code extracted from one capture, plus the capture itself. The M2 write captures (#336) keep their
/// `form` oracles, same schema, in `Fixtures/M2-writes/` (HFR-PROTOCOL §6c "M2 write captures").
struct Lot004FormOracle {
    /// Case id such as `R41a`.
    let id: String
    /// Text of the captured page the legacy code read.
    let html: String
    /// `result.legacy`: the legacy extraction (`formAction`, `inputData`, `loopOrder`, `contentForm`, `subcats`, `smileys`…).
    let legacy: [String: Any]

    static let subdirectory = "Fixtures/LOT-004"
    /// Folder of the M2 write captures' oracles (#336).
    static let m2Subdirectory = "Fixtures/M2-writes"
    /// The `form` cases of `Fixtures/M2-writes/`: the group owner's and a member's reply composers (with and without `newdest`,
    /// #336, #507), the new-MP form.
    static let m2FormCases: Set = ["R123c", "R123e", "R123k", "R124", "R127", "R128", "R132", "R136", "R137", "R138", "R139"]

    /// Folder of the M2 misc captures' oracles (#527, wired by #475).
    static let miscSubdirectory = "Fixtures/M2-misc"
    /// The `form` cases of `Fixtures/M2-misc/`: the edit and quote forms of an MP whose body starts with a line break.
    static let miscFormCases: Set = ["R130b", "R130c"]

    /// The oracle of a case id, from `Fixtures/LOT-004`, or from `Fixtures/M2-writes` or `Fixtures/M2-misc` for an M2 case.
    static func load(_ id: String) throws -> Lot004FormOracle {
        let folder = m2FormCases.contains(id) ? m2Subdirectory : miscFormCases.contains(id) ? miscSubdirectory : subdirectory
        let root = try object(Fixture.text("\(id).oracle", extension: "json", subdirectory: folder))
        #expect(root["kind"] as? String == "form")
        let input = try #require(root["input"] as? [String: Any])
        let file = try #require(input["file"] as? String)
        let capture = file.split(separator: "/").last.map { String($0).replacing(".html", with: "") } ?? file
        let result = try #require(root["result"] as? [String: Any])
        return Lot004FormOracle(id: id, html: try Fixture.capture(capture), legacy: try #require(result["legacy"] as? [String: Any]))
    }

    /// Case ids of the `oracle-map.json` of `folder` (LOT-004 by default) whose kind is `form`.
    static func mappedFormCases(in folder: String = subdirectory) throws -> Set<String> {
        let map = try object(Fixture.text("oracle-map", extension: "json", subdirectory: folder))
        return Set(map.compactMap { key, value in
            (value as? [String: Any])?["kind"] as? String == "form" ? key.replacing(".html", with: "") : nil
        })
    }

    private static func object(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
}
