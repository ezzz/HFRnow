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
                    ForumLink(title: "Known", path: "/hfr/apple/liste_sujet-1.htm"),
                    ForumLink(title: "Unknown", path: "/hfr/nowhere/liste_sujet-1.htm")
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
        #expect(sections?.first?.rows.map(\.source) == [
            .forum(.forum(1), title: "Hardware"), .forum(.forum(25), title: "Known"), nil
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
        model.reveal(.forum(.forum(25), title: "Known"))
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
