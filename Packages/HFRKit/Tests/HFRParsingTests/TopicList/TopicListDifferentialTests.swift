import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// ADR 0004: the parser reproduces the legacy oracle (LOT-002) on every captured list page, field by field.
/// Each deliberate deviation is checked against independent evidence instead, and is listed in
/// `docs/lots/LOT-022-topic-list-parser.md` under "Intentional differences from legacy".
@Suite("Topic list parser, differential against the LOT-002 oracle")
struct TopicListDifferentialTests {
    /// Every `topics`, `mp` and search-results case of `Fixtures/LOT-002/oracle-map.json`, with the category the port
    /// reads from the header search form where legacy left `currentCat` empty (D2). Message pages have none.
    static let cases: [DifferentialCase] = [
        DifferentialCase("R04", category: "13"),
        DifferentialCase("R05a", category: "13"),
        DifferentialCase("R05b", category: "13"),
        DifferentialCase("R06", category: "13"),
        DifferentialCase("R07", category: "12"),
        DifferentialCase("R08-1", category: nil),
        DifferentialCase("R08-2", category: "13"),
        DifferentialCase("R08-3", category: nil),
        DifferentialCase("R09", category: "13"),
        DifferentialCase("R27-list", category: "10"),
        DifferentialCase("P03f", category: "13"),
        DifferentialCase("R13a", category: "prive"),
        DifferentialCase("R13b", category: "prive"),
        DifferentialCase("R13c", category: "prive"),
        DifferentialCase("R13u1", category: "prive"),
        DifferentialCase("R13u1b", category: "prive"),
        DifferentialCase("R50b", category: "13"),
        DifferentialCase("R50c", category: nil)
    ]

    @Test("The case list covers every list oracle of the map")
    func coversEveryListOracle() throws {
        let json = try Fixture.text("oracle-map", extension: "json", subdirectory: "Fixtures/LOT-002")
        let map = try JSONDecoder().decode([String: MapEntry].self, from: Data(json.utf8))
        var listCases = Set<String>()
        for (file, entry) in map where ["topics", "mp", "search"].contains(entry.kind) {
            let name = String(file.dropLast(".html".count))
            // The search waiting page (R50a) is a redirect, parsed by LOT-025, not a list.
            if try TopicListOracle.load(name).result?.page != "redirect" {
                listCases.insert(name)
            }
        }
        #expect(Set(Self.cases.map(\.name)) == listCases)
    }

    @Test("Page fields match the oracle", arguments: cases)
    func pageFieldsMatch(_ testCase: DifferentialCase) throws {
        let oracle = try TopicListOracle.load(testCase.name)
        #expect(oracle.schema == 1)
        #expect(oracle.exception == nil)
        let legacy = try #require(oracle.result)
        let page = try TopicListParser.parse(oracle.capture(), pageURL: try #require(oracle.input.currentURL))

        // Navigation: "" (no link) and nil (no pager) both mean "no path".
        #expect(page.navigation.current == legacy.pageNumber)
        #expect(page.navigation.first == legacy.firstPageNumber)
        #expect(page.navigation.last == legacy.lastPageNumber)
        #expect(page.navigation.firstPath == legacy.firstPageUrl.nonEmpty)
        #expect(page.navigation.lastPath == legacy.lastPageUrl.nonEmpty)
        #expect(page.navigation.nextPath == legacy.nextPageUrl.nonEmpty)
        #expect(page.navigation.previousPath == legacy.previousPageUrl.nonEmpty)

        #expect(page.tabs.all == legacy.forumBaseURL)
        #expect(page.tabs.favorites == legacy.forumFavorisURL)
        #expect(page.tabs.flagBlue == legacy.forumFlag1URL)
        #expect(page.tabs.flagRed == legacy.forumFlag0URL)
        #expect(page.newTopicPath == legacy.forumNewTopicUrl.nonEmpty)

        // D2: legacy reads the category from the logged-in search tab only; where it did, the port agrees.
        if let legacyCategory = legacy.currentCat.nonEmpty {
            #expect(page.categoryID?.queryValue == legacyCategory)
        }
        #expect(page.categoryID?.queryValue == testCase.category)

        // D6: the badge is a number; legacy's "\u{a0}Messages privés" (no digit) is 0.
        let expectedBadge = try #require(legacy.needToUpdateMP) ? Int(legacy.sNewMPNumber ?? "") ?? 0 : nil
        #expect(page.unreadPrivateMessages == expectedBadge)

        // D1: `noAuth` pages are empty pages with the message; `noResults` ("Aucun message", a constant) has none.
        switch legacy.statusInfo?.statusName {
        case "noAuth":
            #expect(page.notice == legacy.statusInfo?.message)
            #expect(page.topics.isEmpty)
        case "noResults":
            #expect(page.notice == nil)
            #expect(page.topics.isEmpty)
        default:
            #expect(legacy.statusInfo == nil)
            #expect(page.notice == nil)
        }
    }

    @Test("Rows match the oracle field by field", arguments: cases)
    func rowsMatch(_ testCase: DifferentialCase) throws {
        let oracle = try TopicListOracle.load(testCase.name)
        let html = try oracle.capture()
        let page = try TopicListParser.parse(html, pageURL: try #require(oracle.input.currentURL))
        let legacyRows = try #require(oracle.result).topics ?? []
        let evidence = CaptureRowEvidence(html: html)
        try #require(page.topics.count == legacyRows.count)
        try #require(evidence.rows.count == legacyRows.count)

        for (index, (row, legacy)) in zip(page.topics, legacyRows).enumerated() {
            let context = Comment(rawValue: "\(testCase.name) row \(index)")
            // D4: the title stays raw; legacy's "TU" rewrite applied to it gives the oracle's title.
            #expect(LegacyTitleRewrite.filterTU(row.title) == legacy.aTitle, context)
            #expect(row.path == legacy.aURL, context)
            #expect(row.firstPagePath == legacy.aURLOfFirstPage.nonEmpty, context)
            #expect(row.repliesCount == legacy.aRepCount, context)
            #expect(row.pageCount == legacy.maxTopicPage, context)
            #expect(row.lastPagePath == legacy.aURLOfLastPage, context)
            #expect(row.lastPost?.path == legacy.aURLOfLastPost, context)
            #expect(row.lastPost?.author == legacy.aAuthorOfLastPost, context)
            #expect(row.lastPost?.date == legacy.dDateOfLastPost.flatMap { try? Date($0, strategy: .iso8601) }, context)
            #expect(row.flag?.legacyName ?? "" == legacy.aTypeOfFlag, context)
            #expect(row.flagPath == legacy.aURLOfFlag.nonEmpty, context)
            #expect(row.currentPage ?? 0 == legacy.curTopicPage, context)
            #expect(row.readState == (legacy.isViewed ? .read : .unread), context)
            #expect(row.isSticky == legacy.isSticky, context)
            #expect(row.isClosed == legacy.isClosed, context)
            // D7: the snippet is trimmed (legacy kept HFR's trailing space).
            #expect(row.searchHit?.postPath == legacy.sLastSearchPostURL, context)
            #expect(row.searchHit?.snippet == legacy.sLastSearchPostContent.map(CaptureRowEvidence.trimmingWhiteSpace), context)

            // D3: plain-text starters (anonymous pages), which legacy left empty, come from the cell text.
            if legacy.aAuthorOrInter.isEmpty {
                #expect(row.starterOrInterlocutors == evidence.starterText(row: index), context)
                #expect(!row.starterOrInterlocutors.isEmpty, context)
            } else {
                #expect(row.starterOrInterlocutors == legacy.aAuthorOrInter, context)
            }
            // D5: polls are detected on the live icon; legacy never found one in a list (LOT-002 RC2.3).
            #expect(!legacy.isPoll, context)
            #expect(row.isPoll == evidence.showsPollIcon(row: index), context)
            // Session state legacy does not parse: constant on list pages, so nothing is lost by not modelling it.
            #expect(legacy.isViewedFromForumAtLoad == legacy.isViewed, context)
            #expect(!legacy.isLocallyViewedInApp && !legacy.isSuperFavorite, context)
            // D8: topic identity (legacy lists left `catID`/`postID` at 0).
            #expect(legacy.catID == 0 && legacy.postID == 0, context)
            #expect(row.topicID?.topic == evidence.topicNumber(row: index), context)
            #expect(row.topicID?.category.queryValue == testCase.category, context)
        }
    }

    // MARK: - Support

    struct DifferentialCase: Sendable, CustomTestStringConvertible {
        let name: String
        let category: String?

        init(_ name: String, category: String?) {
            self.name = name
            self.category = category
        }

        var testDescription: String { name }
    }

    private struct MapEntry: Decodable {
        let kind: String
    }
}

private extension Optional where Wrapped == String {
    /// Legacy's "" and nil both mean "absent".
    var nonEmpty: String? {
        self.flatMap { $0.isEmpty ? nil : $0 }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private extension TopicFlag {
    /// `aTypeOfFlag` value of legacy (`ObjCTopicListParser.m:347-355`).
    var legacyName: String { rawValue }
}
