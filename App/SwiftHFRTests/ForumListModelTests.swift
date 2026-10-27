import Foundation
import HFRNetwork
import HFRModels
@testable import SwiftHFR
import Testing

@MainActor
struct ForumListModelTests {
    private let page = ForumListPage(
        forums: [
            ForumCategory(
                categoryID: .forum(1), title: "Hardware", path: "/hfr/Hardware/liste_sujet-1.htm",
                subforums: [
                    ForumLink(title: "Mini PC", path: "/hfr/Hardware/minipc/liste_sujet-1.htm"),
                    ForumLink(title: "Bench", path: "/hfr/Hardware/Benchs/liste_sujet-1.htm")
                ]
            ),
            ForumCategory(categoryID: .forum(25), title: "Apple", path: "/hfr/apple/liste_sujet-1.htm")
        ],
        isLoggedIn: true,
        unreadPrivateMessages: 2
    )

    @Test func appliesTheAppleRuleAndResolvesSources() async {
        let source = FakeDataSource()
        let page = page
        source.forumHandler = { page }
        let model = ForumListModel(dataSource: source, accountName: { "someone" })
        await model.loadIfNeeded()
        let sections = model.loader.value?.sections
        #expect(sections?.map(\.title) == ["Hardware", "Apple"])
        // Every sub-forum opens from the link the home page gave, whether or not the catalogue knows it.
        #expect(sections?.first?.rows.map(\.source) == [
            .forum(.forum(1), title: "Hardware"),
            .subforum(path: "/hfr/Hardware/minipc/liste_sujet-1.htm", title: "Mini PC"),
            .subforum(path: "/hfr/Hardware/Benchs/liste_sujet-1.htm", title: "Bench")
        ])
        #expect(model.loader.value?.unreadPrivateMessages == 2)
    }

    @Test func theReviewAccountDoesNotSeeTheAppleCategory() async {
        let source = FakeDataSource()
        let page = page
        source.forumHandler = { page }
        let model = ForumListModel(dataSource: source, accountName: { "applereview" })
        await model.loadIfNeeded()
        #expect(model.loader.value?.sections.map(\.title) == ["Hardware"])
    }

    @Test func aFailedReloadKeepsTheForumList() async {
        let source = FakeDataSource()
        let page = page
        source.forumHandler = { page }
        let model = ForumListModel(dataSource: source)
        await model.loadIfNeeded()
        source.forumHandler = { () async throws(ListLoadError) -> ForumListPage in throw .maintenance("Maintenance en cours") }
        await model.reload()
        #expect(model.loader.value?.sections.count == 1)
        #expect(model.loader.error == .maintenance("Maintenance en cours"))
    }

    @Test func revealOpensTheSectionOfTheSelection() async {
        let source = FakeDataSource()
        let page = page
        source.forumHandler = { page }
        let model = ForumListModel(dataSource: source, accountName: { "someone" })
        await model.loadIfNeeded()
        model.reveal(.subforum(path: "/hfr/Hardware/minipc/liste_sujet-1.htm", title: "Mini PC"))
        #expect(model.expandedSections == ["/hfr/Hardware/liste_sujet-1.htm"])
    }
}

struct ListLoadErrorTests {
    @Test func mapsTransportAndParserFailures() {
        #expect(ListLoadError(.offline) == .offline)
        #expect(ListLoadError(.cancelled) == .cancelled)
        #expect(ListLoadError(.httpStatus(code: 503, url: URL(string: "https://forum.hardware.fr/")!)) == .server(status: 503))
        #expect(ListLoadError(ListPageFailure.malformed("x")) == .unreadable)
        #expect(ListLoadError(ListPageFailure.maintenance("m")) == .maintenance("m"))
    }
}

struct SubforumPathTests {
    @Test func replacesThePageOfAListPath() {
        #expect(SubforumPath.page(3, of: "/hfr/Hardware/minipc/liste_sujet-1.htm") == "/hfr/Hardware/minipc/liste_sujet-3.htm")
        #expect(SubforumPath.page(12, of: "/hfr/Hardware/liste_sujet-7.htm") == "/hfr/Hardware/liste_sujet-12.htm")
    }

    @Test func refusesWhatIsNotAListPathOrPage() {
        #expect(SubforumPath.page(1, of: "/forum2.php?cat=1") == nil)
        #expect(SubforumPath.page(0, of: "/hfr/Hardware/liste_sujet-1.htm") == nil)
    }

    @Test func frenchPluralTreatsZeroAndOneAsSingular() {
        #expect(FrenchPlural.count(0, "réponse", "réponses") == "0 réponse")
        #expect(FrenchPlural.count(1, "page", "pages") == "1 page")
        #expect(FrenchPlural.count(2, "page", "pages") == "2 pages")
    }

    @Test func everyFailureHasASymbolAndMaintenanceIsNotAWifiIcon() {
        #expect(ListLoadError.maintenance("m").symbol != ListLoadError.offline.symbol)
        #expect(ListLoadError.server(status: 500).symbol == "exclamationmark.triangle")
    }
}
