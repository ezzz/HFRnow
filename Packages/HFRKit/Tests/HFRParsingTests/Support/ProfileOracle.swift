import Foundation

/// The LOT-005 oracle of a public profile (`Fixtures/LOT-005/<case>.oracle.json`, kind `profile`): the legacy
/// `UserProfile` exactly as exported, URLs as strings, the "Non renseigné" placeholder text included.
struct ProfileOracle: Decodable {
    struct Summary: Decodable, Equatable {
        var id: String
        var systemImage: String
        var title: String
        var value: String
    }

    struct Field: Decodable, Equatable {
        var id: String
        var isPlaceholder: Bool
        var title: String
        var url: String?
        var value: String
    }

    struct Section: Decodable, Equatable {
        var id: String
        var title: String
        var fields: [Field]
    }

    struct Smiley: Decodable, Equatable {
        var id: String
        var code: String
        var imageURL: String
        var title: String?
    }

    struct Action: Decodable, Equatable {
        var id: String
        var kind: String
        var subtitle: String?
        var title: String
        var url: String
    }

    struct Profile: Decodable, Equatable {
        var pseudo: String
        var status: String?
        var avatarURL: String?
        var summary: [Summary]
        var sections: [Section]
        var personalSmilies: [Smiley]
        var actions: [Action]
    }

    struct Result: Decodable {
        var profile: Profile?
        var error: String?
    }

    struct Input: Decodable {
        var file: String
    }

    /// One entry of `oracle-map.json`.
    struct MapEntry: Decodable {
        var kind: String
        var path: String
    }

    var exception: String?
    var input: Input
    var result: Result

    /// Fixtures subdirectory holding the small-parser oracles.
    static let subdirectory = "Fixtures/LOT-005"

    /// The oracle of a case id such as `R56a`.
    static func load(_ caseID: String) throws -> ProfileOracle {
        let json = try Fixture.text("\(caseID).oracle", extension: "json", subdirectory: subdirectory)
        return try JSONDecoder().decode(ProfileOracle.self, from: Data(json.utf8))
    }

    /// Case ids of the map entries of kind `profile` (`R56a.html` → `R56a`).
    static func profileCases() throws -> Set<String> {
        let json = try Fixture.text("oracle-map", extension: "json", subdirectory: subdirectory)
        let map = try JSONDecoder().decode([String: MapEntry].self, from: Data(json.utf8))
        return Set(map.filter { $0.value.kind == "profile" }.map { $0.key.replacing(".html", with: "") })
    }

    /// The capture the oracle was exported from.
    func capture() throws -> String {
        let name = input.file.split(separator: "/").last.map(String.init) ?? input.file
        return try Fixture.capture(name.replacing(".html", with: ""))
    }
}
