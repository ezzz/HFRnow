import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// LOT-068 on captured topic pages: what a cookie-less fetch returns (`R20`, `R22a`, `R22b`, `R23`, `R28`) round-trips,
/// a page fetched with the session (`R21`, `R32b`) is refused. File-level edges use files written by the test.
@Suite("Offline topic store")
struct OfflineTopicStoreTests {
    private static let pizza = TopicID(category: .forum(13), topic: 28563)
    private static let tequila = TopicID(category: .forum(13), topic: 91031)
    private static let now = Date(timeIntervalSinceReferenceDate: 815_000_000.123_456)

    /// The capture `file` of the shared corpus, read in place (it is a resource of `HFRParsingTests`).
    private static func capture(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "HFRParsingTests/Fixtures/captures/\(file).html")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func page(_ topic: TopicID, _ number: Int, _ file: String, at date: Date = now) throws -> OfflinePage {
        OfflinePage(topic: topic, page: number, title: "Pizza maison", html: try capture(file), savedAt: date)
    }

    private static func withStore(limit: Int = 50, _ body: (OfflineTopicStore, TemporaryCache) throws -> Void) throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        try body(OfflineTopicStore(cache: temp.cache, maximumPagesPerTopic: limit), temp)
    }

    private static func file(_ topic: TopicID, _ number: Int, in temp: TemporaryCache) -> URL {
        guard case .forum(let category) = topic.category else { return temp.base }
        return temp.cache.url(for: .offlineTopics).appending(path: "\(category)-\(topic.topic)/\(number).json")
    }

    // MARK: - Round trip

    @Test(
        "A captured page fetched without cookies loads back as saved, byte for byte",
        arguments: [
            (pizza, 1, "R20-topic-p1-anon"), (pizza, 1100, "R22a-topic-middle-page-anon"),
            (pizza, 2201, "R22b-topic-last-page-anon"), (tequila, 1, "R23-topic-single-page-anon"),
            (TopicID(category: .forum(13), topic: 78667), 15990, "R28-topic-images-videos-anon")
        ]
    )
    func roundTrip(topic: TopicID, number: Int, file: String) throws {
        try Self.withStore { store, temp in
            let saved = try Self.page(topic, number, file)
            try store.save(saved)
            #expect(try store.page(number, of: topic) == saved)
            #expect(try store.page(number + 1, of: topic) == nil)
            #expect(Self.file(topic, number, in: temp).path().contains("/cache/offline/13-\(topic.topic)/\(number).json"))
        }
    }

    @Test("The list shows each topic's pages ascending, the title of its highest page, the most recent topic first")
    func list() throws {
        try Self.withStore { store, temp in
            try store.save(Self.page(Self.pizza, 2201, "R22b-topic-last-page-anon"))
            let middle = try Self.capture("R22a-topic-middle-page-anon")
            try store.save(OfflinePage(topic: Self.pizza, page: 1100, title: "Ancien titre", html: middle, savedAt: Self.now))
            try store.save(Self.page(Self.tequila, 1, "R23-topic-single-page-anon"))
            // Whole seconds: some file systems keep no sub-second modification dates.
            let base = Date(timeIntervalSinceReferenceDate: 815_000_000)
            for (topic, page, age) in [(Self.pizza, 1100, 300.0), (Self.pizza, 2201, 200), (Self.tequila, 1, 100)] {
                try FileManager.default.setAttributes(
                    [.modificationDate: base.addingTimeInterval(-age)], ofItemAtPath: Self.file(topic, page, in: temp).path()
                )
            }
            let topics = try store.topics()
            #expect(topics.map(\.topic) == [Self.tequila, Self.pizza])
            #expect(topics.last?.pages == [1100, 2201])
            #expect(topics.last?.title == "Pizza maison")
            #expect(topics.last?.lastSavedAt == base.addingTimeInterval(-200))
        }
    }

    @Test("Saving a page again replaces it: the app saves the topic's last page each time, since it grows")
    func replaceLastPage() throws {
        try Self.withStore { store, _ in
            try store.save(Self.page(Self.pizza, 2201, "R24-topic-beyond-last-page-anon"))
            let newer = try Self.page(Self.pizza, 2201, "R22b-topic-last-page-anon", at: Self.now.addingTimeInterval(60))
            try store.save(newer)
            #expect(try store.page(2201, of: Self.pizza) == newer)
            #expect(try store.topics().first?.pages == [2201])
        }
    }

    // MARK: - Refusals

    @Test("A page fetched with the session holds its token and is never written", arguments: [
        "R21-topic-p1-logged-in", "R32b-topic-poll-logged-in-not-voted"
    ])
    func sessionPages(file: String) throws {
        try Self.withStore { store, temp in
            #expect(throws: OfflineStoreError.containsSessionToken) { try store.save(try Self.page(Self.pizza, 1, file)) }
            #expect(!temp.exists(Self.file(Self.pizza, 1, in: temp)))
        }
    }

    @Test("The token check reads every hash_check input, whatever the quoting; an unreadable value counts as a token")
    func tokenForms() {
        #expect(!OfflinePageRecord.holdsSessionToken(#"<input type="hidden" name="hash_check" value="" />"#))
        #expect(!OfflinePageRecord.holdsSessionToken(#"<input name="other" value="x"><input name=hash_check value=''>"#))
        #expect(OfflinePageRecord.holdsSessionToken(#"<input value="" name="x"><INPUT NAME='hash_check' VALUE='t0k3n'>"#))
        #expect(OfflinePageRecord.holdsSessionToken(#"<input type="hidden" name="hash_check">"#))
        #expect(OfflinePageRecord.holdsSessionToken(#"<input name="hash_check" value="" /><input name="hash_check" value="a">"#))
        // A `>` inside a quoted attribute does not end the tag (LESSONS 34).
        #expect(OfflinePageRecord.holdsSessionToken(#"<input title="a>b" name="hash_check" value="t0k3n">"#))
        #expect(!OfflinePageRecord.holdsSessionToken(#"<input title='a>b' name="hash_check" value="">"#))
        // A quote never closed: the tag still counts, and its value cannot be read, so it is a token (fail closed).
        #expect(OfflinePageRecord.holdsSessionToken(#"<input name="hash_check" value="t0k3n>"#))
    }

    @Test("Only forum topics from page 1, with content, are saved", arguments: [
        (TopicID(category: .privateMessages, topic: 3207033), 1), (TopicID(category: .forum(0), topic: 1), 1),
        (TopicID(category: .forum(13), topic: 0), 1), (TopicID(category: .forum(13), topic: 28563), 0)
    ])
    func invalidTopic(topic: TopicID, number: Int) throws {
        try Self.withStore { store, _ in
            #expect(throws: OfflineStoreError.invalidTopic) {
                try store.save(OfflinePage(topic: topic, page: number, title: "t", html: "<p>page</p>", savedAt: Self.now))
            }
        }
    }

    @Test("An empty page is refused")
    func emptyPage() throws {
        try Self.withStore { store, _ in
            #expect(throws: OfflineStoreError.emptyPage) {
                try store.save(OfflinePage(topic: Self.pizza, page: 1, title: "t", html: "", savedAt: Self.now))
            }
        }
    }

    // MARK: - Page limit and eviction

    @Test("Beyond the per-topic limit the lowest pages go; a page below a full topic's pages is refused")
    func pageLimit() throws {
        try Self.withStore(limit: 3) { store, _ in
            for number in [10, 11, 12, 13] {
                try store.save(OfflinePage(topic: Self.pizza, page: number, title: "t", html: "<p>\(number)</p>", savedAt: Self.now))
            }
            #expect(try store.topics().first?.pages == [11, 12, 13])
            #expect(throws: OfflineStoreError.beyondPageLimit) {
                try store.save(OfflinePage(topic: Self.pizza, page: 10, title: "t", html: "<p>10</p>", savedAt: Self.now))
            }
            try store.save(OfflinePage(topic: Self.pizza, page: 13, title: "t", html: "<p>13 bis</p>", savedAt: Self.now))
            #expect(try store.topics().first?.pages == [11, 12, 13])
            let floor = OfflineTopicStore(cache: CacheDirectory(root: URL.temporaryDirectory), maximumPagesPerTopic: 0)
            #expect(floor.maximumPagesPerTopic == 1)
        }
    }

    @Test("The offline area keeps pages whatever their age and evicts the oldest past its budget; the rest still loads")
    func eviction() throws {
        #expect(CacheArea.offlineTopics.evictionPolicy == .offlineTopics)
        #expect(CacheEvictionPolicy.offlineTopics.maximumAge == nil)
        #expect(CacheEvictionPolicy.offlineTopics.maximumTotalBytes == 200_000_000)
        try Self.withStore { store, temp in
            try store.save(Self.page(Self.pizza, 1, "R20-topic-p1-anon"))
            try store.save(Self.page(Self.pizza, 2, "R20-topic-p1-anon"))
            let old = Self.file(Self.pizza, 1, in: temp)
            try FileManager.default.setAttributes([.modificationDate: Self.now.addingTimeInterval(-400 * 86_400)], ofItemAtPath: old.path())
            #expect(temp.cache.evictAll(now: Self.now)[.offlineTopics]?.removedFileCount == 0)
            let bound = try #require(try FileManager.default.attributesOfItem(atPath: old.path())[.size] as? Int)
            _ = CacheEvictor.evict(
                directory: temp.cache.url(for: .offlineTopics), policy: CacheEvictionPolicy(maximumTotalBytes: bound), now: Self.now
            )
            #expect(!temp.exists(old))
            #expect(try store.topics().first?.pages == [2])
            #expect(try store.page(2, of: Self.pizza)?.page == 2)
        }
    }

    @Test("Removing a topic removes its pages only; removing all empties the area")
    func removal() throws {
        try Self.withStore { store, _ in
            try store.save(Self.page(Self.pizza, 1, "R20-topic-p1-anon"))
            try store.save(Self.page(Self.tequila, 1, "R23-topic-single-page-anon"))
            try store.remove(Self.pizza)
            #expect(try store.topics().map(\.topic) == [Self.tequila])
            #expect(try store.page(1, of: Self.pizza) == nil)
            try store.removeAll()
            #expect(try store.topics().isEmpty)
        }
    }
}
