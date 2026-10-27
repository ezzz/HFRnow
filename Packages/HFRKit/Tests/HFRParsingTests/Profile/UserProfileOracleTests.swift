import Foundation
import Testing
@testable import HFRParsing

/// Differential tests (ADR 0004): the full profile of R56a and R56b must equal the legacy export.
@Suite("User profile against the legacy oracle")
struct UserProfileOracleTests {
    /// Every `profile` case of `Fixtures/LOT-005/oracle-map.json`.
    static let cases = ["R56a", "R56b"]

    @Test("the case list covers every profile case of the oracle map")
    func casesCoverTheMap() throws {
        #expect(try ProfileOracle.profileCases() == Set(Self.cases))
    }

    @Test("the oracles come from the legacy parser without exception", arguments: cases)
    func oracleIsUsable(id: String) throws {
        let oracle = try ProfileOracle.load(id)
        #expect(oracle.exception == nil)
        #expect(oracle.result.error == nil)
        #expect(oracle.result.profile != nil)
    }

    @Test("pseudo, status, avatar, summary, sections, smileys and actions equal the oracle", arguments: cases)
    func matchesOracle(id: String) throws {
        let oracle = try ProfileOracle.load(id)
        let profile = try UserProfileParser.parse(html: oracle.capture())
        let expected = try #require(oracle.result.profile)
        #expect(Self.legacyShape(of: profile) == expected)
    }

    @Test("the typed figures read the dates and the count of the oracle's strings", arguments: cases)
    func typedFigures(id: String) throws {
        let oracle = try ProfileOracle.load(id)
        let profile = try UserProfileParser.parse(html: oracle.capture())
        let summary = Dictionary(uniqueKeysWithValues: try #require(oracle.result.profile).summary.map { ($0.id, $0.value) })
        #expect(profile.messageCount == summary["Nombre de messages postés"].flatMap { Int($0) })
        #expect(profile.joinDate == summary["Date d'arrivée sur le forum"].flatMap(Self.parisDay))
        #expect(profile.lastMessageDate == summary["Date du dernier message"].flatMap(HFRDate.date(from:)))
        #expect(profile.messageCount != nil && profile.joinDate != nil && profile.lastMessageDate != nil)
    }

    // MARK: - Mapping to the oracle's shape

    /// Re-expresses the parser's value as the legacy export: display texts and icons that legacy stored are rebuilt here, so
    /// the comparison covers every legacy field while the model keeps display choices out (spec, "Intentional differences").
    static func legacyShape(of profile: UserProfile) -> ProfileOracle.Profile {
        ProfileOracle.Profile(
            pseudo: profile.pseudo,
            status: profile.status,
            avatarURL: profile.avatarURL?.absoluteString,
            summary: profile.summary.map { item in
                let label = Self.summaryLabels[item.kind] ?? ("", "")
                return .init(id: item.kind.fieldTitle, systemImage: label.image, title: label.title, value: item.value)
            },
            sections: profile.sections.map { section in
                .init(id: section.id, title: section.title, fields: section.fields.map { field in
                    .init(
                        id: field.id,
                        isPlaceholder: field.isPlaceholder,
                        title: field.title,
                        url: field.url?.absoluteString,
                        value: field.isPlaceholder ? "Non renseigné" : field.value
                    )
                })
            },
            personalSmilies: profile.personalSmilies.map {
                .init(id: $0.id, code: $0.code, imageURL: $0.imageURL.absoluteString, title: $0.title)
            },
            actions: profile.actions.map {
                .init(id: $0.id, kind: $0.kind.rawValue, subtitle: $0.subtitle, title: $0.title, url: $0.url.absoluteString)
            }
        )
    }

    static let summaryLabels: [UserProfileSummaryItem.Kind: (title: String, image: String)] = [
        .messageCount: ("Messages", "text.bubble"),
        .joinDate: ("Arrivée", "calendar"),
        .lastMessageDate: ("Dernier", "clock")
    ]

    /// `dd/MM/yyyy` as midnight Paris, written independently of the parser (through `HFRDate`'s printed form).
    static func parisDay(_ text: String) -> Date? {
        let parts = text.split(separator: "/")
        guard parts.count == 3 else { return nil }
        return HFRDate.date(from: "\(parts[0])-\(parts[1])-\(parts[2]) à 00:00")
    }
}
