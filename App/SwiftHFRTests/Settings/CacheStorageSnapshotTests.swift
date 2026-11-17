import Foundation
import HFRStorage
@testable import SwiftHFR
import Testing

struct CacheStorageSnapshotTests {
    /// A temporary `Caches` folder with a `cache/pages` area, removed by the test.
    private func withCaches(_ body: (URL, URL) throws -> Void) throws {
        let caches = URL.temporaryDirectory.appending(path: "lot179-\(UUID().uuidString)", directoryHint: .isDirectory)
        let pages = caches.appending(path: "cache/pages", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: caches) }
        try body(caches, pages)
    }

    private func write(_ bytes: Int, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url)
    }

    @Test func anEmptyCacheMeasuresZero() throws {
        try withCaches { caches, pages in
            #expect(CacheStorageSnapshot.measure(cachesDirectory: caches, pagesDirectory: pages)
                == CacheStorageSnapshot(totalBytes: 0, htmlBytes: 0, htmlFileCount: 0))
        }
    }

    @Test func missingFoldersMeasureZero() {
        let missing = URL.temporaryDirectory.appending(path: "lot179-missing-\(UUID().uuidString)", directoryHint: .isDirectory)
        #expect(CacheStorageSnapshot.measure(cachesDirectory: missing, pagesDirectory: missing)
            == CacheStorageSnapshot(totalBytes: 0, htmlBytes: 0, htmlFileCount: 0))
        #expect(CacheStorageSnapshot.measure(cachesDirectory: missing, pagesDirectory: nil).htmlFileCount == 0)
    }

    @Test func pagesAreCountedAndTheTotalCoversEveryFolder() throws {
        try withCaches { caches, pages in
            try write(5_000, to: pages.appending(path: "topic-A.htm"))
            try write(6_000, to: pages.appending(path: "topic-B.HTM"))
            try write(7_000, to: caches.appending(path: "cache/avatars/x.png"))
            try write(8_000, to: caches.appending(path: "com.apple.other/y.bin"))
            let snapshot = CacheStorageSnapshot.measure(cachesDirectory: caches, pagesDirectory: pages)
            #expect(snapshot.htmlFileCount == 2)
            #expect(snapshot.htmlBytes >= 11_000)
            #expect(snapshot.totalBytes >= snapshot.htmlBytes + 15_000)
            #expect(snapshot.totalBytes > snapshot.htmlBytes)
        }
    }

    @Test func onlyTopicHTMFilesCountAsPages() throws {
        try withCaches { caches, pages in
            try write(1_000, to: pages.appending(path: "topic-1.htm"))
            try write(1_000, to: pages.appending(path: "page-2.htm"))
            try write(1_000, to: pages.appending(path: "topic-3.html"))
            try write(1_000, to: pages.appending(path: "topic-4.txt"))
            try write(1_000, to: pages.appending(path: ".topic-5.htm"))
            try write(1_000, to: pages.appending(path: "nested/topic-6.htm"))
            #expect(CacheStorageSnapshot.measure(cachesDirectory: caches, pagesDirectory: pages).htmlFileCount == 1)
        }
    }

    @Test func hiddenFilesAndFoldersAreLeftOutOfTheTotal() throws {
        try withCaches { caches, pages in
            let visible = CacheStorageSnapshot.measure(cachesDirectory: caches, pagesDirectory: pages).totalBytes
            try write(50_000, to: caches.appending(path: ".hidden-file"))
            try write(50_000, to: caches.appending(path: ".hidden-folder/inside.bin"))
            #expect(CacheStorageSnapshot.measure(cachesDirectory: caches, pagesDirectory: pages).totalBytes == visible)
        }
    }

    @Test func aFolderNamedLikeAPageIsNotCounted() throws {
        try withCaches { caches, pages in
            try FileManager.default.createDirectory(
                at: pages.appending(path: "topic-folder.htm", directoryHint: .isDirectory), withIntermediateDirectories: true
            )
            #expect(CacheStorageSnapshot.measure(cachesDirectory: caches, pagesDirectory: pages).htmlFileCount == 0)
        }
    }

    @Test func aSymbolicLinkIsNotFollowed() throws {
        try withCaches { caches, pages in
            let outside = URL.temporaryDirectory.appending(path: "lot179-out-\(UUID().uuidString)", directoryHint: .isDirectory)
            try write(100_000, to: outside.appending(path: "topic-out.htm"))
            defer { try? FileManager.default.removeItem(at: outside) }
            let fileManager = FileManager.default
            try fileManager.createSymbolicLink(
                at: pages.appending(path: "topic-link.htm"), withDestinationURL: outside.appending(path: "topic-out.htm")
            )
            try fileManager.createSymbolicLink(at: caches.appending(path: "linked"), withDestinationURL: outside)
            let snapshot = CacheStorageSnapshot.measure(cachesDirectory: caches, pagesDirectory: pages)
            #expect(snapshot.htmlFileCount == 0)
            #expect(snapshot.totalBytes < 100_000)
        }
    }

    @Test func textsFollowTheLegacyWording() {
        #expect(CacheStorageText.size(0) == 0.formatted(.byteCount(style: .file)))
        #expect(CacheStorageText.size(20_000_000) == Int64(20_000_000).formatted(.byteCount(style: .file)))
        #expect(CacheStorageText.fileCount(0) == "0 fichier")
        #expect(CacheStorageText.fileCount(1) == "1 fichier")
        #expect(CacheStorageText.fileCount(2) == "2 fichiers")
        #expect(CacheStorageText.fileCount(137) == "137 fichiers")
    }

    @Test func theFooterStatesSwiftHFRsTopicPageRule() {
        #expect(CacheStorageText.purgeRule()
            == "Les pages HTML de plus d’un jour sont supprimées automatiquement. Leur cache est limité à 20 Mo.")
        let legacy = CacheEvictionPolicy(maximumAge: 7 * 86_400, maximumTotalBytes: 50_000_000)
        #expect(CacheStorageText.purgeRule(for: legacy)
            == "Les pages HTML de plus de 7 jours sont supprimées automatiquement. Leur cache est limité à 50 Mo.")
        #expect(CacheStorageText.purgeRule(for: .offlineTopics) == "Leur cache est limité à 200 Mo.")
    }
}
