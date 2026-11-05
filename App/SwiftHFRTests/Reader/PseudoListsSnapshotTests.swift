import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// LOT-117: the reader reads the stored pseudo lists through a snapshot refreshed before each page.
@MainActor
struct PseudoListsSnapshotTests {
    private func store() async throws -> PseudoListStore {
        let store = PseudoListStore(persistence: InMemoryPseudoListPersistence())
        try await store.block("Troll", account: "moi")
        try await store.block("AutreCompte", account: "autre")
        try await store.allow("Ami")
        return store
    }

    @Test func theSnapshotIsEmptyUntilRefreshedThenHoldsTheAccountsBlocklistAndTheAllowlist() async throws {
        let snapshot = PseudoListsSnapshot(store: try await store(), account: "Moi")
        #expect(snapshot.current == PseudoLists())
        await snapshot.refresh()
        #expect(snapshot.current == PseudoLists(blocklist: ["Troll"], allowlist: ["Ami"]))
    }

    @Test func loggedOutOnlyTheAllowlistIsRead() async throws {
        let snapshot = PseudoListsSnapshot(store: try await store(), account: nil)
        await snapshot.refresh()
        #expect(snapshot.current == PseudoLists(blocklist: [], allowlist: ["Ami"]))
    }

    @Test func aLaterChangeOfTheStoreShowsAtTheNextRefresh() async throws {
        let lists = try await store()
        let snapshot = PseudoListsSnapshot(store: lists, account: "moi")
        await snapshot.refresh()
        try await lists.unblock("Troll", account: "moi")
        #expect(snapshot.current.blocklist == ["Troll"])
        await snapshot.refresh()
        #expect(snapshot.current.blocklist.isEmpty)
    }

    @Test func theReaderPageIsBuiltWithTheListsReadJustBeforeItsLoad() async throws {
        let snapshot = PseudoListsSnapshot(store: try await store(), account: "moi")
        let pages = FakeTopicPages { target in
            var page = readerPage(page: target.page)
            page.messages[0].author = "troll"
            return page
        }
        let settings = ReaderSettings.live(
            store: InMemorySettingsStore(), isOnWiFi: { true }, pseudo: "moi", pseudoLists: { snapshot.current }
        )
        let model = TopicReaderModel(
            target: ReaderTarget(source: .topic(readerTopic), page: 1), title: "Sujet",
            source: RefreshingTopicPageSource(base: pages, lists: snapshot), renderOptions: settings.renderOptions
        )
        await model.onAppear()
        let html = try #require(model.document?.html)
        #expect(html.contains("<article class=\"message blocked\""))
        #expect(html.contains("<details class=\"blocked-post\">"))
    }
}
