import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// The page file format: versioned JSON, read without ever crashing on a file this build did not write.
@Suite("Offline page format")
struct OfflinePageFormatTests {
    private static let pizza = TopicID(category: .forum(13), topic: 28563)

    private static func withPages(_ body: (OfflineTopicStore, URL, TemporaryCache) throws -> Void) throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let store = OfflineTopicStore(cache: temp.cache)
        try store.save(OfflinePage(topic: pizza, page: 2, title: "Pizza maison", html: "<p>deux</p>", savedAt: Date()))
        let folder = temp.cache.url(for: .offlineTopics).appending(path: "13-28563", directoryHint: .isDirectory)
        try body(store, folder, temp)
    }

    private static func json(version: Int, page: Int = 1, category: Int = 13, topic: Int = 28563) -> Data {
        let fields = #""html":"<p>un</p>","page":\#(page),"savedAt":0,"title":"t","topic":\#(topic),"version":\#(version)"#
        return Data(#"{"category":\#(category),"#.utf8 + Data(fields.utf8) + Data("}".utf8))
    }

    @Test("A file is versioned JSON with sorted keys and the exact save date")
    func fileFormat() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let date = Date(timeIntervalSince1970: 1.000_000_1)
        let saved = OfflinePage(topic: Self.pizza, page: 1, title: "Pizza", html: "<p>é</p>", savedAt: date)
        try OfflineTopicStore(cache: temp.cache).save(saved)
        let file = temp.cache.url(for: .offlineTopics).appending(path: "13-28563/1.json")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.hasPrefix(#"{"category":13,"html":"<p>é<\/p>","page":1,"savedAt":"#))
        #expect(text.hasSuffix(#""title":"Pizza","topic":28563,"version":1}"#))
        #expect(try OfflineTopicStore(cache: temp.cache).page(1, of: Self.pizza) == saved)
    }

    @Test("A page of another format version is reported, never loaded; the list still shows the topic", arguments: [0, 2, -1])
    func otherVersion(version: Int) throws {
        try Self.withPages { store, folder, _ in
            try Self.json(version: version).write(to: folder.appending(path: "1.json"))
            #expect(throws: OfflineStoreError.unsupportedVersion(version)) { try store.page(1, of: Self.pizza) }
            #expect(try store.topics().first?.pages == [1, 2])
            #expect(try store.topics().first?.title == "Pizza maison")
        }
    }

    @Test("A damaged file is unreadable, never a crash", arguments: [
        "", "{", "null", #"{"version":"1"}"#, #"{"version":1}"#, #"{"version":1,"page":1}"#
    ])
    func damaged(content: String) throws {
        try Self.withPages { store, folder, _ in
            try Data(content.utf8).write(to: folder.appending(path: "1.json"))
            #expect(throws: OfflineStoreError.unreadable) { try store.page(1, of: Self.pizza) }
            #expect(try store.page(2, of: Self.pizza)?.title == "Pizza maison")
        }
    }

    @Test("A file whose content names another page or topic than its place is not that page")
    func misplaced() throws {
        try Self.withPages { store, folder, _ in
            try Self.json(version: 1, page: 7).write(to: folder.appending(path: "1.json"))
            #expect(throws: OfflineStoreError.unreadable) { try store.page(1, of: Self.pizza) }
            try Self.json(version: 1, page: 1, topic: 1).write(to: folder.appending(path: "1.json"))
            #expect(throws: OfflineStoreError.unreadable) { try store.page(1, of: Self.pizza) }
            try Self.json(version: 1, page: 0).write(to: folder.appending(path: "1.json"))
            #expect(throws: OfflineStoreError.unreadable) { try store.page(1, of: Self.pizza) }
        }
    }

    @Test("A record naming no forum topic or no page is unreadable on its own, wherever it sits")
    func recordFields() {
        for data in [Self.json(version: 1, page: 0), Self.json(version: 1, category: 0), Self.json(version: 1, topic: 0)] {
            #expect(throws: OfflineStoreError.unreadable) { try OfflinePageRecord.decode(data) }
        }
        #expect((try? OfflinePageRecord.decode(Self.json(version: 1)))?.topic == Self.pizza)
    }

    @Test("Files and folders the store did not name are ignored by the list")
    func strayFiles() throws {
        try Self.withPages { store, folder, temp in
            let area = temp.cache.url(for: .offlineTopics)
            for name in ["01.json", "1.txt", "-1.json", "x.json", "2.json.tmp"] {
                try Data("x".utf8).write(to: folder.appending(path: name))
            }
            for name in ["prive-3", "13-0", "13", "a-b", "013-28563"] {
                let stray = area.appending(path: name, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)
                try Data("x".utf8).write(to: stray.appending(path: "1.json"))
            }
            try FileManager.default.createDirectory(at: folder.appending(path: "3.json"), withIntermediateDirectories: true)
            let topics = try store.topics()
            #expect(topics.map(\.topic) == [Self.pizza])
            #expect(topics.first?.pages == [2])
            #expect(try store.page(3, of: Self.pizza) == nil)
        }
    }

    @Test("A topic folder that is a symbolic link is never read nor written")
    func linkedFolder() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let outside = temp.base.appending(path: "outside", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let area = try temp.cache.prepare(.offlineTopics)
        try FileManager.default.createSymbolicLink(at: area.appending(path: "13-28563"), withDestinationURL: outside)
        let store = OfflineTopicStore(cache: temp.cache)
        let page = OfflinePage(topic: Self.pizza, page: 1, title: "t", html: "<p>x</p>", savedAt: Date())
        #expect(throws: OfflineStoreError.unsafeFolder) { try store.save(page) }
        #expect(throws: OfflineStoreError.unsafeFolder) { try store.page(1, of: Self.pizza) }
        #expect(try store.topics().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path()).isEmpty)
    }

    @Test("A page file that is a symbolic link is neither listed nor read")
    func linkedPageFile() throws {
        try Self.withPages { store, folder, temp in
            let target = temp.base.appending(path: "elsewhere.json")
            try Self.json(version: 1).write(to: target)
            try FileManager.default.createSymbolicLink(at: folder.appending(path: "1.json"), withDestinationURL: target)
            #expect(try store.topics().first?.pages == [2])
            #expect(throws: OfflineStoreError.unsafeFolder) { try store.page(1, of: Self.pizza) }
        }
    }
}
