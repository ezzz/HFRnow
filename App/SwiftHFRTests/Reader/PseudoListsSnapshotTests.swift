import Foundation
import HFRClient
import HFRModels
import HFRParsing
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

    @Test func aChangeOfTheListsRebuildsTheShownPageWithoutARequest() async throws {
        let lists = try await store()
        let snapshot = PseudoListsSnapshot(store: lists, account: "moi")
        let pages = FakeTopicPages { target in
            var page = readerPage(page: target.page)
            page.messages[0].author = "Nouveau"
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
        let first = try #require(model.document)
        #expect(!first.html.contains("class=\"message blocked\""))
        model.applyDisplaySettings() // nothing changed: the same document
        #expect(model.document == first)
        try await lists.block("Nouveau", account: "moi")
        await snapshot.refresh()
        model.applyDisplaySettings()
        let second = try #require(model.document)
        #expect(second.token > first.token)
        #expect(second.html.contains("<article class=\"message blocked\""))
        #expect(second.keepsScrollPosition)
        #expect(pages.requests.count == 1)
    }

    private struct PassNormalizer: MessageContentNormalizing {
        func normalize(contentHTML: String, pageURL: URL) throws(ParsingError) -> MessageContent {
            MessageContent(html: contentHTML)
        }
    }

    @Test func aFilteredPostsRunReadsTheStoredAllowlistWithNoReaderLoadBefore() async throws {
        let lists = try await store()
        try await lists.allow("Troll") // blocklisted too: legacy's `isWL:` refuses it
        let snapshot = PseudoListsSnapshot(store: lists, account: "moi")
        let source = FakeFilteredSource { _, _, _ in filteredBatch(start: 1, end: 1) }
        let services = FilteredPostsServices(
            source: source,
            criteria: {
                FilteredPostsServices.criteria(
                    store: InMemorySettingsStore(), pseudo: "moi", allowlist: snapshot.current.allowlistWithoutBlocked
                )
            },
            normalizer: PassNormalizer(),
            prepare: { await snapshot.refresh() }
        )
        // Cold launch: nothing has refreshed the snapshot, as when a run starts from a topic list row.
        #expect(snapshot.current == PseudoLists())
        let model = FilteredPostsModel(services: services)
        model.start(topic: readerTopic, title: "Sujet", page: 1, after: nil)
        while model.isRunning { await Task.yield() }
        #expect(source.calls.first?.criteria.allowlist == ["Ami"])
        #expect(source.calls.first?.criteria.includesAllowlist == true)
    }
}
