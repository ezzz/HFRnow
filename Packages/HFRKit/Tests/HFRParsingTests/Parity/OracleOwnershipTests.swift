import Foundation
import Testing

/// LOT-070 gate A: every case of every `Fixtures/*/oracle-map.json` is listed by the suite that compares it with the port.
/// A new folder, a new kind or a new case fails here until a suite owns it (the per-suite coverage tests list only the
/// folders their authors knew: LESSONS 60).
@Suite("Oracle ownership (LOT-070 gate A)")
struct OracleOwnershipTests {
    /// One owner: the (folder, kind) pairs it compares and the `folder/case` ids it lists.
    struct Owner {
        let name: String
        let folders: Set<String>
        let kinds: Set<String>
        let cases: Set<String>
    }

    static var owners: [Owner] {
        [listOwner, favouritesOwner, forumsOwner, topicOwner, formOwner, storageOwner, responseOwner, aqOwner] + lot005Owners
    }

    /// `TopicListDifferentialTests` (lists, MP lists, search results), `PrivateMessageListParserTests` (group MP lists);
    /// `LOT-002/R50a` is the search waiting page, a redirect compared by `SmallParsersOracleTests` (LOT-005 `R50a`).
    static let listOwner = Owner(
        name: "TopicListDifferentialTests, PrivateMessageListParserTests",
        folders: ["LOT-002", "M2-readonly", "M2-misc", "M2-writes"], kinds: ["topics", "mp", "search"],
        cases: Set(TopicListDifferentialTests.allCases.map { "\($0.folder)/\($0.name)" })
            .union(PrivateMessageListParserTests.groupCases.map { "M2-writes/\($0)" })
            .union(["LOT-002/R50a"])
    )

    /// `FavoritesDifferentialTests`: compared cases, the pending `R73b` (#384), and `R12`, `R70b` (legacy raised).
    static let favouritesOwner = Owner(
        name: "FavoritesDifferentialTests",
        folders: ["LOT-002", "M2-writes"], kinds: ["favorites"],
        cases: Set((FavoritesDifferentialTests.cases + FavoritesDifferentialTests.pendingCases + ["R12", "R70b"]).map {
            "\(FavoritesOracle.folders[$0] ?? "LOT-002")/\($0)"
        })
    )

    /// `ForumListParserTests`: the compared home pages and the stale-session page legacy read as empty.
    static let forumsOwner = Owner(
        name: "ForumListParserTests",
        folders: ["LOT-002"], kinds: ["forums"],
        cases: Set((ForumListParserTests.captures.map(\.oracle) + [ForumListParserTests.staleSession.oracle]).map { "LOT-002/\($0)" })
    )

    /// `MessageBlockOracleTests` and `TopicPageMetadataOracleTests` (LOT-003 and the M2 topic pages), `TopicPageFlagOracleTests`
    /// (`LOT-003-flag`), `MessageContentOracleTests` (`LOT-003-settings`).
    static let topicOwner = Owner(
        name: "MessageBlockOracleTests, TopicPageFlagOracleTests, MessageContentOracleTests",
        folders: ["LOT-003", "LOT-003-flag", "LOT-003-settings", "M2-readonly", "M2-misc", "M2-writes"], kinds: ["topic"],
        cases: Set(MessageBlockOracleTests.allCases.map { "\(MessageBlockOracleTests.m2Folders[$0] ?? "LOT-003")/\($0)" })
            .union(TopicPageFlagOracleTests.folders.filter { $0.value == "LOT-003-flag" }.keys.map { "LOT-003-flag/\($0)" })
            .union(MessageContentOracleTests.settingsCases.map { "LOT-003-settings/\($0)" })
    )

    /// `HopFormOracleTests` (and `R46`, the alert form, read by its own test there).
    static let formOwner = Owner(
        name: "HopFormOracleTests",
        folders: ["LOT-004", "M2-writes", "M2-misc"], kinds: ["form"],
        cases: Set((HopFormOracleTests.composerCases + ["R46"]).map { id in
            let folder = Lot004FormOracle.m2FormCases.contains(id) ? "M2-writes"
                : Lot004FormOracle.miscFormCases.contains(id) ? "M2-misc" : "LOT-004"
            return "\(folder)/\(id)"
        })
    )

    /// `MPStoragePageParserTests`.
    static let storageOwner = Owner(
        name: "MPStoragePageParserTests",
        folders: ["LOT-004"], kinds: ["storage"],
        cases: Set(MPStoragePageParserTests.storageCases.map { "LOT-004/\($0)" })
    )

    /// `HopResponseParserTests`.
    static let responseOwner = Owner(
        name: "HopResponseParserTests",
        folders: ["LOT-004", "M2-writes", "M2-misc"], kinds: ["response"],
        cases: Set((HopResponseParserTests.oracleCases + HopResponseParserTests.ownTestCases).map { "LOT-004/\($0)" })
            .union(HopResponseParserTests.rosterCases.map { "M2-writes/\($0)" })
            .union(HopResponseParserTests.miscCases.map { "M2-misc/\($0)" })
    )

    /// `AQParsersTests` (the RSS feed `T01`).
    static let aqOwner = Owner(name: "AQParsersTests", folders: ["LOT-028"], kinds: ["aq-rss"], cases: ["LOT-028/T01"])

    /// `PollOracleTests`, `SmallParsersOracleTests`, `UserProfileOracleTests` on `LOT-005`.
    static let lot005Owners: [Owner] = [
        ("PollOracleTests", "poll", PollOracleTests.cases),
        ("SmallParsersOracleTests", "search-redirect", SmallParsersOracleTests.searchCases),
        ("SmallParsersOracleTests", "smiley-search", SmallParsersOracleTests.smileySearchCases),
        ("SmallParsersOracleTests", "smiley-keywords", SmallParsersOracleTests.wikiCases),
        ("SmallParsersOracleTests", "profile-edit", SmallParsersOracleTests.profileCases + SmallParsersOracleTests.profileRefusalCases),
        ("UserProfileOracleTests", "profile", UserProfileOracleTests.cases)
    ].map { Owner(name: $0.0, folders: ["LOT-005"], kinds: [$0.1], cases: Set($0.2.map { "LOT-005/\($0)" })) }

    /// The bundle's `Fixtures` folder.
    static func fixturesRoot() throws -> URL {
        try #require(Bundle.module.resourceURL?.appending(path: "Fixtures"))
    }

    /// Every `(folder, kind, case)` of every oracle map in the bundle's `Fixtures`.
    static func mappedCases() throws -> [(folder: String, kind: String, id: String)] {
        let root = try fixturesRoot()
        var cases: [(folder: String, kind: String, id: String)] = []
        for folder in try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false)).sorted() {
            guard let json = try? Fixture.text("oracle-map", extension: "json", subdirectory: "Fixtures/\(folder)") else { continue }
            let map = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: [String: Any]])
            for (key, entry) in map {
                let id = URL(fileURLWithPath: key).deletingPathExtension().lastPathComponent
                cases.append((folder, try #require(entry["kind"] as? String, "\(folder)/\(key): kind"), id))
            }
        }
        return cases
    }

    @Test("Every oracle map case has exactly one owner, and every owner lists exactly its cases")
    func everyOracleIsOwned() throws {
        let mapped = try Self.mappedCases()
        // Every `<case>.oracle.json` on disk is a map entry of its folder, and the reverse: no oracle escapes the maps.
        let root = try Self.fixturesRoot()
        var files = Set<String>()
        for folder in try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false)) {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.appending(path: folder).path(percentEncoded: false))
            else { continue }
            files.formUnion(names.filter { $0.hasSuffix(".oracle.json") }.map { "\(folder)/\($0.dropLast(".oracle.json".count))" })
        }
        #expect(files == Set(mapped.map { "\($0.folder)/\($0.id)" }))
        #expect(!mapped.isEmpty)
        for owner in Self.owners {
            let theirs = mapped.filter { owner.folders.contains($0.folder) && owner.kinds.contains($0.kind) }
            #expect(Set(theirs.map { "\($0.folder)/\($0.id)" }) == owner.cases, "\(owner.name)")
        }
        for item in mapped {
            let count = Self.owners.filter { $0.folders.contains(item.folder) && $0.kinds.contains(item.kind) }.count
            #expect(count == 1, "\(item.folder)/\(item.kind)/\(item.id): \(count) owners")
        }
    }
}
