import Testing
@testable import HFRModels

@Suite struct ForumCatalogueTests {
    /// Path and id pairs copied from the legacy table (`Classes/Forum.m:34-60`), independent of `ForumCatalogue.entries`.
    static let legacyRows: [(String, Int)] = [
        ("/hfr/Hardware/liste_sujet-1.htm", 1),
        ("/hfr/HardwarePeripheriques/liste_sujet-1.htm", 16),
        ("/hfr/OrdinateursPortables/liste_sujet-1.htm", 15),
        ("/hfr/gsmgpspda/liste_sujet-1.htm", 23),
        ("/hfr/OverclockingCoolingModding/liste_sujet-1.htm", 2),
        ("/hfr/electroniquedomotiquediy/liste_sujet-1.htm", 30),
        ("/hfr/apple/liste_sujet-1.htm", 25),
        ("/hfr/VideoSon/liste_sujet-1.htm", 3),
        ("/hfr/Photonumerique/liste_sujet-1.htm", 14),
        ("/hfr/JeuxVideo/liste_sujet-1.htm", 5),
        ("/hfr/WindowsSoftware/liste_sujet-1.htm", 4),
        ("/hfr/reseauxpersosoho/liste_sujet-1.htm", 22),
        ("/hfr/systemereseauxpro/liste_sujet-1.htm", 21),
        ("/hfr/OSAlternatifs/liste_sujet-1.htm", 11),
        ("/hfr/Programmation/liste_sujet-1.htm", 10),
        ("/hfr/Graphisme/liste_sujet-1.htm", 12),
        ("/hfr/AchatsVentes/liste_sujet-1.htm", 6),
        ("/hfr/EmploiEtudes/liste_sujet-1.htm", 8),
        ("/hfr/Setietprojetsdistribues/liste_sujet-1.htm", 9),
        ("/hfr/Discussions/liste_sujet-1.htm", 13),
        ("/hfr/Blabla-Divers-back-to-life/liste_sujet-1.htm", 24),
        ("/hfr/ia/liste_sujet-1.htm", 32),
        ("https://forum.hardware.fr/hfr/ia/liste_sujet-1.htm", 32)
    ]

    @Test func tableMatchesLegacyRows() {
        #expect(ForumCatalogue.entries.map(\.path) == Self.legacyRows.map(\.0))
        #expect(ForumCatalogue.entries.map(\.categoryID) == Self.legacyRows.map { CategoryID.forum($0.1) })
    }

    @Test(arguments: legacyRows)
    func everyLegacyRowResolvesToItsId(path: String, id: Int) {
        #expect(ForumCatalogue.categoryID(forPath: path) == .forum(id))
    }

    @Test(arguments: ForumCatalogue.entries)
    func everyTableRowRoundTrips(entry: ForumCatalogueEntry) throws {
        let found = try #require(ForumCatalogue.categoryID(forPath: entry.path))
        #expect(found == entry.categoryID)
        let canonical = try #require(ForumCatalogue.forumPath(for: found))
        #expect(canonical.hasPrefix("/hfr/"))
        #expect(ForumCatalogue.categoryID(forPath: canonical) == entry.categoryID)
    }

    @Test func absoluteIaAliasMapsToTheRelativeCanonicalPath() {
        #expect(ForumCatalogue.categoryID(forPath: "https://forum.hardware.fr/hfr/ia/liste_sujet-1.htm") == .forum(32))
        #expect(ForumCatalogue.forumPath(for: .forum(32)) == "/hfr/ia/liste_sujet-1.htm")
    }

    @Test func twentyTwoForumsAreKnown() {
        let ids = Set(ForumCatalogue.entries.map(\.categoryID))
        #expect(ids.count == 22)
        #expect(ForumCatalogue.entries.count == 23)
    }

    @Test func applePathIsCategory25() {
        #expect(ForumCatalogue.categoryID(forPath: "/hfr/apple/liste_sujet-1.htm") == .forum(25))
        #expect(ForumCatalogue.forumPath(for: .forum(25)) == "/hfr/apple/liste_sujet-1.htm")
    }

    @Test(arguments: [
        "/hfr/Unknown/liste_sujet-1.htm",
        "/hfr/apple/liste_sujet-2.htm",
        "/hfr/apple/liste_sujet-1.htm?page=2",
        "hfr/apple/liste_sujet-1.htm",
        "",
        "/hfr/Apple/liste_sujet-1.htm"
    ])
    func unknownPathsReturnNil(path: String) {
        #expect(ForumCatalogue.categoryID(forPath: path) == nil)
    }

    @Test func unknownCategoryHasNoPath() {
        #expect(ForumCatalogue.forumPath(for: .forum(999)) == nil)
        #expect(ForumCatalogue.forumPath(for: .privateMessages) == nil)
    }
}
