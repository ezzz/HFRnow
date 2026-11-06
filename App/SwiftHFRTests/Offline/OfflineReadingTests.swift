import Foundation
import HFRModels
import HFRParsing
import HFRStorage
@testable import SwiftHFR
import Testing

/// LOT-139: reading saved pages through the reader, and the list. Pages are the LOT-001 captures.
@MainActor
struct OfflineReadingTests {
    private static let canonical = "https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm"

    private static func services(_ cache: OfflineTempCache) -> OfflineServices {
        OfflineServices(
            store: LiveOfflineStore(store: OfflineTopicStore(cache: cache.cache)),
            fetcher: FakeOfflineFetcher { _ throws(ListLoadError) in throw .other },
            normalizer: LiveContentNormalizer()
        )
    }

    private static func save(_ file: String, page: Int, title: String = "Pizza maison", into cache: OfflineTempCache) throws {
        try OfflineTopicStore(cache: cache.cache).save(
            OfflinePage(topic: OfflineCorpus.pizza, page: page, title: title, html: try OfflineCorpus.html(file), savedAt: .now)
        )
    }

    // MARK: - The reader's source

    @Test func aSavedPageReadsLikeTheLivePageOfTheSameHTML() async throws {
        let cache = try OfflineTempCache()
        defer { cache.cleanUp() }
        try Self.save("R20-topic-p1-anon.html", page: 1, into: cache)
        let offline = try await Self.services(cache).pageSource.page(for: ReaderTarget(source: .topic(OfflineCorpus.pizza), page: 1))
        let live = try LiveTopicPageSource.parse(
            try OfflineCorpus.html("R20-topic-p1-anon.html"), pageURL: try #require(URL(string: Self.canonical)),
            normalizer: LiveContentNormalizer()
        )
        #expect(offline.messages.map(\.numreponse) == live.messages.map(\.numreponse))
        #expect(offline.messages.map(\.author) == live.messages.map(\.author))
        #expect(offline.messages.map(\.content) == live.messages.map(\.content))
        #expect(offline.currentPage == 1 && offline.maxPage == live.maxPage)
        #expect(offline.topicID == OfflineCorpus.pizza)
        #expect(!offline.messages.isEmpty)
    }

    @Test func theSavedPageNumberIsTheOneShown() async throws {
        let cache = try OfflineTempCache()
        defer { cache.cleanUp() }
        try Self.save("R22a-topic-middle-page-anon.html", page: 1100, into: cache)
        let page = try await Self.services(cache).pageSource.page(for: ReaderTarget(source: .topic(OfflineCorpus.pizza), page: 1100))
        #expect(page.currentPage == 1100)
    }

    @Test func aPageNeverSavedAndAMessageLinkAreNotSaved() async throws {
        let cache = try OfflineTempCache()
        defer { cache.cleanUp() }
        try Self.save("R20-topic-p1-anon.html", page: 1, into: cache)
        let source = Self.services(cache).pageSource
        await #expect(throws: ListLoadError.notSaved) {
            try await source.page(for: ReaderTarget(source: .topic(OfflineCorpus.pizza), page: 2))
        }
        await #expect(throws: ListLoadError.notSaved) {
            try await source.page(for: ReaderTarget(source: .topic(OfflineCorpus.pizza), page: 1, anchor: 5, numreponse: 5))
        }
    }

    @Test func aDamagedSavedPageIsUnreadableNotBlank() async throws {
        let cache = try OfflineTempCache()
        defer { cache.cleanUp() }
        try Self.save("R20-topic-p1-anon.html", page: 1, into: cache)
        let file = cache.cache.url(for: .offlineTopics).appending(path: "13-28563/1.json")
        try Data("{".utf8).write(to: file)
        await #expect(throws: ListLoadError.savedPageUnreadable) {
            try await Self.services(cache).pageSource.page(for: ReaderTarget(source: .topic(OfflineCorpus.pizza), page: 1))
        }
    }

    @Test func theReaderMovesBetweenSavedPagesAndSaysWhichIsMissing() async throws {
        let cache = try OfflineTempCache()
        defer { cache.cleanUp() }
        try Self.save("R22a-topic-middle-page-anon.html", page: 1100, into: cache)
        try Self.save("R22a-topic-middle-page-anon.html", page: 1101, into: cache)
        let reader = TopicReaderModel(
            target: ReaderTarget(source: .topic(OfflineCorpus.pizza), page: 1100), title: "Pizza maison",
            source: Self.services(cache).pageSource
        )
        await reader.onAppear()
        #expect(reader.page?.currentPage == 1100)
        await reader.goToPage(1101)
        #expect(reader.page?.currentPage == 1101)
        await reader.goToPage(1102)
        #expect(reader.error == .notSaved)
        #expect(reader.page?.currentPage == 1101)
    }

    // MARK: - The list

    @Test func theListShowsSavedTopicsAndDeletesThem() async throws {
        let cache = try OfflineTempCache()
        defer { cache.cleanUp() }
        try Self.save("R20-topic-p1-anon.html", page: 1, into: cache)
        try Self.save("R22a-topic-middle-page-anon.html", page: 1100, into: cache)
        let model = OfflineTopicsModel(services: Self.services(cache))
        await model.load()
        #expect(model.topics.map(\.pages) == [[1, 1100]])
        #expect(model.sizeOnDisk > 0)
        await model.remove(try #require(model.topics.first))
        #expect(model.topics.isEmpty && model.sizeOnDisk == 0 && model.hasLoaded)
    }

    @Test func deleteAllEmptiesTheList() async throws {
        let cache = try OfflineTempCache()
        defer { cache.cleanUp() }
        try Self.save("R20-topic-p1-anon.html", page: 1, into: cache)
        let model = OfflineTopicsModel(services: Self.services(cache))
        await model.load()
        #expect(model.topics.count == 1)
        await model.removeAll()
        #expect(model.topics.isEmpty && model.errorMessage == nil)
    }

    @Test func aFailedDeletionKeepsItsReasonThroughTheReload() async throws {
        let cache = try OfflineTempCache()
        defer { cache.cleanUp() }
        try Self.save("R20-topic-p1-anon.html", page: 1, into: cache)
        let saved = try #require(try OfflineTopicStore(cache: cache.cache).topics().first)
        let services = OfflineServices(
            store: FailingDeleteStore(), fetcher: FakeOfflineFetcher { _ throws(ListLoadError) in throw .other },
            normalizer: LiveContentNormalizer()
        )
        let model = OfflineTopicsModel(services: services)
        await model.load()
        await model.removeAll()
        #expect(model.errorMessage == OfflineStoreError.fileFailed(reason: "x").message)
        await model.remove(saved)
        #expect(model.errorMessage == OfflineStoreError.fileFailed(reason: "x").message)
    }

    @Test func aDamagedSavedPageTellsTheMemberToDeleteIt() async throws {
        let cache = try OfflineTempCache()
        defer { cache.cleanUp() }
        try Self.save("R20-topic-p1-anon.html", page: 1, into: cache)
        try Data("{".utf8).write(to: cache.cache.url(for: .offlineTopics).appending(path: "13-28563/1.json"))
        await #expect(throws: ListLoadError.savedPageUnreadable) {
            try await Self.services(cache).pageSource.page(for: ReaderTarget(source: .topic(OfflineCorpus.pizza), page: 1))
        }
        #expect(ListLoadError.savedPageUnreadable.detail.contains("Supprimez"))
    }

    @Test func aPrivateConversationIsNotSaved() async throws {
        let cache = try OfflineTempCache()
        defer { cache.cleanUp() }
        let topic = TopicID(category: .privateMessages, topic: 5)
        await #expect(throws: ListLoadError.notSaved) {
            try await Self.services(cache).pageSource.page(for: ReaderTarget(source: .topic(topic), page: 1))
        }
    }

    @Test func theListOrdersEqualDatesByForumThenTopic() throws {
        let cache = try OfflineTempCache()
        defer { cache.cleanUp() }
        let store = OfflineTopicStore(cache: cache.cache)
        let html = try OfflineCorpus.html("R20-topic-p1-anon.html")
        let date = Date(timeIntervalSinceReferenceDate: 1)
        for (forum, number) in [(13, 9), (2, 9), (100, 1), (13, 3), (5, 5)] {
            let topic = TopicID(category: .forum(forum), topic: number)
            try store.save(OfflinePage(topic: topic, page: 1, title: "", html: html, savedAt: date))
            // The list reads the files' own dates: make them equal, but for the newest topic.
            let file = cache.cache.url(for: .offlineTopics).appending(path: "\(forum)-\(number)/1.json")
            try FileManager.default.setAttributes(
                [.modificationDate: forum == 5 ? date.addingTimeInterval(10) : date], ofItemAtPath: file.path(percentEncoded: false)
            )
        }
        let ordered = OfflineTopicsModel.displayOrder(try store.topics())
        #expect(ordered.map { "\($0.topic.category.queryValue)-\($0.topic.topic)" } == ["5-5", "2-9", "13-3", "13-9", "100-1"])
    }

    @Test func pageCountsReadInFrench() {
        #expect(OfflinePageCount.text([4]) == "page 4")
        #expect(OfflinePageCount.text([4, 5, 6]) == "pages 4 à 6")
        #expect(OfflinePageCount.text([1, 5, 9]) == "3 pages")
    }
}

/// A store whose deletions fail and whose list is empty.
private struct FailingDeleteStore: OfflineStoring {
    func save(_ page: OfflinePage) async throws(OfflineStoreError) {}
    func topics() async throws(OfflineStoreError) -> [OfflineTopic] { [] }
    func page(_ number: Int, of topic: TopicID) async throws(OfflineStoreError) -> OfflinePage? { nil }
    func remove(_ topic: TopicID) async throws(OfflineStoreError) { throw .fileFailed(reason: "x") }
    func removeAll() async throws(OfflineStoreError) { throw .fileFailed(reason: "x") }
    func sizeOnDisk() async -> Int { 0 }
    func evict() async {}
}
