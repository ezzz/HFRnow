import Foundation
@testable import HFRStorage
import Testing

@Suite("Legacy page cache (LOT-067)")
struct LegacyPageCacheTests {
    private let fileManager = FileManager.default

    private func write(_ name: String, in folder: URL) throws {
        try Data("x".utf8).write(to: folder.appending(path: name))
    }

    @Test("removes topic-*.htm at the root of Caches/cache, any case of extension, and nothing else")
    func removesOnlyLegacyPages() throws {
        let caches = try LegacySamples.temporaryFolder()
        defer { try? fileManager.removeItem(at: caches) }
        let cache = caches.appending(path: "cache", directoryHint: .isDirectory)
        let avatars = cache.appending(path: "avatars", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: avatars, withIntermediateDirectories: true)
        for name in ["topic-1.htm", "topic-ABC.HTM", "topic-2.html", "page-3.htm", "topic-4.htm.bak", "style-liste.css"] {
            try write(name, in: cache)
        }
        try write("topic-5.htm", in: avatars)
        try fileManager.createDirectory(at: cache.appending(path: "topic-dir.htm"), withIntermediateDirectories: true)

        let result = LegacyPageCache.removePages(cachesDirectory: caches)

        #expect(result == LegacyPageCache.Result(removed: 2, failed: 0, folderMissing: false))
        let left = try fileManager.contentsOfDirectory(atPath: cache.path(percentEncoded: false)).sorted()
        #expect(left == ["avatars", "page-3.htm", "style-liste.css", "topic-2.html", "topic-4.htm.bak", "topic-dir.htm"])
        #expect(fileManager.fileExists(atPath: avatars.appending(path: "topic-5.htm").path(percentEncoded: false)))
    }

    @Test("never follows a link: a linked page or a linked cache folder is left, and its target too")
    func symbolicLinks() throws {
        let root = try LegacySamples.temporaryFolder()
        defer { try? fileManager.removeItem(at: root) }
        let outside = root.appending(path: "outside", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        try write("topic-target.htm", in: outside)

        let caches = root.appending(path: "caches", directoryHint: .isDirectory)
        let cache = caches.appending(path: "cache", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: cache, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(
            at: cache.appending(path: "topic-link.htm"), withDestinationURL: outside.appending(path: "topic-target.htm")
        )
        #expect(LegacyPageCache.removePages(cachesDirectory: caches).removed == 0)
        #expect(fileManager.fileExists(atPath: outside.appending(path: "topic-target.htm").path(percentEncoded: false)))

        let linkedCaches = root.appending(path: "linked", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: linkedCaches, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: linkedCaches.appending(path: "cache"), withDestinationURL: outside)
        let linked = LegacyPageCache.removePages(cachesDirectory: linkedCaches)
        #expect(linked.folderMissing && linked.removed == 0)
        #expect(fileManager.fileExists(atPath: outside.appending(path: "topic-target.htm").path(percentEncoded: false)))
    }

    @Test("a missing cache folder is nothing to do")
    func missingFolder() throws {
        let caches = try LegacySamples.temporaryFolder()
        defer { try? fileManager.removeItem(at: caches) }
        #expect(LegacyPageCache.removePages(cachesDirectory: caches).folderMissing)
    }
}
