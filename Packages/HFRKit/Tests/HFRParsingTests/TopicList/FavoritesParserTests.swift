import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// ADR 0004: the favourites parser reproduces the legacy oracle (LOT-002) on every captured favourites page.
/// Deliberate deviations are listed in `docs/lots/LOT-024-favourites-parser.md`.
@Suite("Favourites parser, differential against the LOT-002 oracle")
struct FavoritesDifferentialTests {
    /// Every `favorites` case of `Fixtures/LOT-002/oracle-map.json` that legacy parsed (R12 raised).
    static let cases = ["R10", "R11", "P03c", "P03e"]

    @Test("The case list covers every favourites oracle of the map")
    func coversEveryFavouritesOracle() throws {
        let json = try Fixture.text("oracle-map", extension: "json", subdirectory: "Fixtures/LOT-002")
        let map = try JSONDecoder().decode([String: MapEntry].self, from: Data(json.utf8))
        let names = map.filter { $0.value.kind == "favorites" }.map { String($0.key.dropLast(".html".count)) }
        #expect(Set(Self.cases + ["R12"]) == Set(names))
    }

    @Test("Page facts and sections match the oracle", arguments: cases)
    func sectionsMatch(_ name: String) throws {
        let oracle = try FavoritesOracle.load(name)
        #expect(oracle.schema == 1)
        #expect(oracle.exception == nil)
        let legacy = try #require(oracle.result)
        let page = try FavoritesParser.parse(oracle.capture())

        #expect(page.unreadPrivateMessages == oracle.sideEffects.nbMP)
        #expect((page.hashCheck != nil) == (oracle.sideEffects.hashCheck != nil))
        try #require(page.sections.count == legacy.favorites.count)
        for (index, (section, legacySection)) in zip(page.sections, legacy.favorites).enumerated() {
            let context = Comment(rawValue: "\(name) section \(index)")
            #expect(legacySection.order == index, context)
            #expect(section.forum.path == legacySection.forum.aURL, context)
            #expect(section.forum.title == legacySection.forum.aTitle, context)
            #expect(section.categoryID?.queryValue == legacySection.forum.aID, context)
            #expect(section.topics.count == legacySection.topics.count, context)
        }
    }

    @Test("Rows match the oracle field by field", arguments: cases)
    func rowsMatch(_ name: String) throws {
        let oracle = try FavoritesOracle.load(name)
        let html = try oracle.capture()
        let page = try FavoritesParser.parse(html)
        let legacySections = try #require(oracle.result).favorites
        let evidence = CaptureRowEvidence(html: html)
        let rows = page.sections.flatMap(\.topics)
        let legacyRows = legacySections.flatMap(\.topics)
        try #require(rows.count == legacyRows.count)
        try #require(evidence.rows.count == legacyRows.count)

        for (index, (row, legacy)) in zip(rows, legacyRows).enumerated() {
            let context = Comment(rawValue: "\(name) row \(index)")
            // D4: the title stays raw; legacy's "TU" rewrite applied to it gives the oracle's title.
            #expect(LegacyTitleRewrite.filterTU(row.title) == legacy.aTitle, context)
            // The resume path (flag link, else last post) is legacy's `aURL`; the title link is its first page.
            #expect(row.path == legacy.aURL, context)
            #expect(row.firstPagePath == legacy.aURLOfFirstPage, context)
            #expect(row.repliesCount == legacy.aRepCount, context)
            #expect(row.pageCount == legacy.maxTopicPage, context)
            #expect(row.lastPagePath == legacy.aURLOfLastPage, context)
            #expect(row.lastPost?.path == legacy.aURLOfLastPost, context)
            #expect(row.lastPost?.author == legacy.aAuthorOfLastPost, context)
            #expect(row.lastPost?.date == legacy.dDateOfLastPost.flatMap { try? Date($0, strategy: .iso8601) }, context)
            #expect(row.currentPage == legacy.curTopicPage, context)
            #expect(row.topicID?.category.queryValue == String(legacy.catID), context)
            #expect(row.topicID?.topic == legacy.postID, context)
            #expect(row.isSticky == legacy.isSticky, context)
            #expect(row.isClosed == legacy.isClosed, context)
            // D5: polls are detected on the live icon (legacy matched it too, on the exact URL).
            #expect(row.isPoll == legacy.isPoll, context)
            #expect(row.isPoll == evidence.showsPollIcon(row: index), context)
            #expect(row.topicID?.topic == evidence.topicNumber(row: index), context)

            // D1: unknown, not legacy's "viewed unless flagged" (`isViewed` is true only for a row without flag link).
            #expect(row.readState == .unknown, context)
            // D2: the flag link and colour are kept; legacy left `aURLOfFlag` and `aTypeOfFlag` empty here.
            #expect(legacy.aURLOfFlag.isEmpty && legacy.aTypeOfFlag.isEmpty, context)
            #expect(row.flagPath == legacy.aURL, context)
            #expect(row.flagPath != nil && !legacy.isViewed, context)
            #expect(row.flag != nil, context)
            // D3: the starter is read (legacy never filled `aAuthorOrInter` on this page).
            #expect(legacy.aAuthorOrInter.isEmpty, context)
            #expect(!row.starterOrInterlocutors.isEmpty, context)
        }
    }

    @Test("The flat list by last post matches the oracle order", arguments: cases)
    func topicsByLastPostMatch(_ name: String) throws {
        let oracle = try FavoritesOracle.load(name)
        let page = try FavoritesParser.parse(oracle.capture())
        let expected = try #require(oracle.result).topicsSortedByLastPostDesc.map { "\($0.catID)-\($0.postID)" }
        #expect(page.topicsByLastPost.map { "\($0.topicID?.category.queryValue ?? "?")-\($0.topicID?.topic ?? 0)" } == expected)
    }

    @Test("A message page is an empty page carrying HFR's message (R12)")
    func messagePage() throws {
        let oracle = try FavoritesOracle.load("R12")
        #expect(oracle.exception == "FavoritesLoadError: Aucun sujet que vous avez lu n'est connu")
        #expect(oracle.result == nil)
        let page = try FavoritesParser.parse(oracle.capture())
        #expect(page.notice == "Aucun sujet que vous avez lu n'est connu")
        #expect(page.sections.isEmpty)
        #expect(page.hashCheck == nil)
    }

    private struct MapEntry: Decodable {
        let kind: String
    }
}

@Suite("Favourites parser")
struct FavoritesParserTests {
    @Test("Colours and read position come from the flag cell: blue on a tracked list (R10), yellow on favourites (P03c)")
    func flags() throws {
        let tracked = try FavoritesParser.parse(Fixture.capture("R10-favourites-owntopic1"))
        #expect(tracked.sections.flatMap(\.topics).map(\.flag) == [.blue, .blue])
        #expect(tracked.sections.flatMap(\.topics).map(\.currentPage) == [1700, 3763])
        let favourites = try FavoritesParser.parse(Fixture.capture("P03c-favourites-after-addflag"))
        #expect(favourites.sections.flatMap(\.topics).map(\.flag) == [.yellow])
    }

    @Test("An account without favourite is an empty page, not a failure (R11, P03e)", arguments: [
        "R11-favourites-owntopic3-empty", "P03e-favourites-after-delflag-empty"
    ])
    func emptyList(_ capture: String) throws {
        let page = try FavoritesParser.parse(Fixture.capture(capture))
        #expect(page.sections.isEmpty)
        #expect(page.notice == nil)
        #expect(page.topicsByLastPost.isEmpty)
    }

    @Test("A page that is not a list is malformed (topic page, R20)")
    func notAList() throws {
        #expect(throws: ListPageFailure.malformed("page without list body or message")) {
            try FavoritesParser.parse(Fixture.capture("R20-topic-p1-anon"))
        }
    }

    @Test("The token is kept for the caller and hidden from descriptions")
    func tokenIsRedacted() throws {
        let page = try FavoritesParser.parse(Fixture.capture("R10-favourites-owntopic1"))
        let token = try #require(page.hashCheck)
        #expect(!token.isEmpty)
        #expect(!page.description.contains(token))
        #expect(!String(reflecting: page).contains(token))
        #expect(!String(describing: Mirror(reflecting: page).children.map { "\($0.value)" }).contains(token))
    }

    // MARK: - Non-regression (docs/LOTS.md, issues to open #1) and unsafe links, derived from captures

    @Test("A last-page link without href keeps the rows: one page, title link as last page")
    func lastPageLinkWithoutHref() throws {
        let html = try Fixture.capture("R10-favourites-owntopic1")
            .replacing(#/<td class="sujetCase4"><a href="[^"]*"/#, with: #"<td class="sujetCase4"><a"#)
        let rows = try FavoritesParser.parse(html).sections.flatMap(\.topics)
        #expect(rows.count == 2)
        #expect(rows.map(\.pageCount) == [1, 1])
        #expect(rows.map(\.lastPagePath) == rows.compactMap(\.firstPagePath))
    }

    @Test("A flag link to another site is dropped: the row resumes at its last post")
    func foreignFlagLink() throws {
        let html = try Fixture.capture("R10-favourites-owntopic1")
            .replacing(#/<td class="sujetCase5"><a href="[^"]*"/#, with: #"<td class="sujetCase5"><a href="https://evil.example/x""#)
        let rows = try FavoritesParser.parse(html).sections.flatMap(\.topics)
        #expect(rows.map(\.flagPath) == [nil, nil])
        #expect(rows.map(\.path) == rows.compactMap(\.lastPost?.path))
        #expect(rows.map(\.currentPage) == [1815, 8639])
    }

    private static let secondRow = #"<tr class="sujet ligne_booleen cBackCouleurTab3 " >"#

    @Test("A second category header starts a second section (R10 with its second row moved under a new header)")
    func secondHeader() throws {
        let link = #"<a href="/forum1.php?config=hfr.inc&amp;cat=9" class="cHeader">Other</a>"#
        let header = #"<tr class="cBackHeader fondForum1fCat"><th>"# + link + "</th></tr>"
        let html = try Fixture.capture("R10-favourites-owntopic1").replacing(Self.secondRow, with: header + Self.secondRow)
        let sections = try FavoritesParser.parse(html).sections
        #expect(sections.map(\.forum.title) == ["Emploi & Etudes", "Other"])
        #expect(sections.map { $0.categoryID?.queryValue } == ["8", "9"])
        #expect(sections.map(\.topics.count) == [1, 1])
    }

    @Test("A later header without link must not drop its rows silently: malformed, not a partial list")
    func laterHeaderWithoutLink() throws {
        let header = #"<tr class="cBackHeader fondForum1fCat"><th><a class="cHeader">Broken</a></th></tr>"#
        let html = try Fixture.capture("R10-favourites-owntopic1").replacing(Self.secondRow, with: header + Self.secondRow)
        #expect(throws: ListPageFailure.malformed("1 of 2 rows not under a readable category header")) {
            try FavoritesParser.parse(html)
        }
    }

    @Test("Only the rows of table.main count (legacy :103-104): without that table, rows are not placed")
    func tableMainScoping() throws {
        let html = try Fixture.capture("R10-favourites-owntopic1")
            .replacing(#"<table class="main" cellspacing="0" cellpadding="2"><form name="form1""#,
                       with: #"<table class="other" cellspacing="0" cellpadding="2"><form name="form1""#)
        #expect(throws: ListPageFailure.malformed("2 of 2 rows not under a readable category header")) {
            try FavoritesParser.parse(html)
        }
    }

    @Test("A category header without link makes its rows unplaceable: malformed, not an empty list")
    func headerWithoutLink() throws {
        let html = try Fixture.capture("R10-favourites-owntopic1")
            .replacing(#/<a href="/forum1\.php[^"]*" class="cHeader">/#, with: #"<a class="cHeader">"#)
        #expect(throws: ListPageFailure.malformed("2 of 2 rows not under a readable category header")) {
            try FavoritesParser.parse(html)
        }
    }
}
