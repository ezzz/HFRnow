import Foundation
import Testing
@testable import HFRStorage

@Suite struct TemporaryFileCacheTests {
    @Test func writesUniquelyNamedFilesInThePagesArea() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let files = TemporaryFileCache(cache: temp.cache)
        let first = try files.write("<html>é</html>")
        let second = try files.write("<html>é</html>")
        #expect(first != second)
        #expect(first.deletingLastPathComponent() == files.directoryURL)
        #expect(first.pathExtension == "htm")
        #expect(first.lastPathComponent.hasPrefix("topic-"))
        #expect(try String(contentsOf: first, encoding: .utf8) == "<html>é</html>")
    }

    @Test func customPrefixAndExtension() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let url = try TemporaryFileCache(cache: temp.cache).write(Data([1]), prefix: "mp", pathExtension: "html")
        #expect(url.lastPathComponent.hasPrefix("mp-"))
        #expect(url.pathExtension == "html")
    }

    @Test func oldPagesAreEvictedAtLaunchButRecentOnesStay() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let files = TemporaryFileCache(cache: temp.cache)
        let old = try files.write("old")
        let recent = try files.write("recent")
        let now = Date.now
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-2 * 86_400)], ofItemAtPath: old.path())
        temp.cache.evictAll(now: now)
        #expect(!temp.exists(old))
        #expect(temp.exists(recent))
    }

    @Test func areasUseSeparateFolders() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        #expect(Set(CacheArea.allCases.map { temp.cache.url(for: $0).lastPathComponent }) == ["avatars", "pages"])
        #expect(CacheDirectory.standard.root.lastPathComponent == "cache")
    }

    @Test(arguments: ["../x", "a/b", "..", ".", "", "a b", "é", "x.y", String(repeating: "a", count: 33)])
    func unsafePrefixesAndExtensionsAreRejected(component: String) throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let files = TemporaryFileCache(cache: temp.cache)
        #expect(throws: CacheError.invalidFileName) { try files.write(Data([1]), prefix: component) }
        #expect(throws: CacheError.invalidFileName) { try files.write(Data([1]), pathExtension: component) }
        #expect(!FileManager.default.fileExists(atPath: temp.base.appending(path: "x").path()))
    }
}
