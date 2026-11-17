import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

struct CacheStorageSnapshotTests {
    /// A temporary `Caches` folder holding `cache/` (with its `offline` area), removed by the test.
    private func withCaches(_ body: (_ caches: URL, _ cache: CacheDirectory, _ offline: URL) throws -> Void) throws {
        let caches = URL.temporaryDirectory.appending(path: "lot179-\(UUID().uuidString)", directoryHint: .isDirectory)
        let cache = CacheDirectory(root: caches.appending(path: "cache", directoryHint: .isDirectory))
        let offline = cache.url(for: .offlineTopics)
        try FileManager.default.createDirectory(at: offline, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: caches) }
        try body(caches, cache, offline)
    }

    private func write(_ bytes: Int, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url)
    }

    @Test func anEmptyCacheMeasuresZero() throws {
        try withCaches { caches, cache, _ in
            #expect(CacheStorageSnapshot.measure(cachesDirectory: caches, cache: cache)
                == CacheStorageSnapshot(totalBytes: 0, htmlBytes: 0, htmlFileCount: 0))
        }
    }

    @Test func missingFoldersMeasureZero() {
        let missing = URL.temporaryDirectory.appending(path: "lot179-missing-\(UUID().uuidString)", directoryHint: .isDirectory)
        let cache = CacheDirectory(root: missing.appending(path: "cache", directoryHint: .isDirectory))
        #expect(CacheStorageSnapshot.measure(cachesDirectory: missing, cache: cache)
            == CacheStorageSnapshot(totalBytes: 0, htmlBytes: 0, htmlFileCount: 0))
    }

    @Test func aPageSavedByTheOfflineStoreIsCounted() throws {
        try withCaches { caches, cache, _ in
            let store = OfflineTopicStore(cache: cache)
            let topic = TopicID(category: .forum(13), topic: 28_563)
            #expect(CacheStorageSnapshot.measure(cachesDirectory: caches, cache: cache).htmlFileCount == 0)
            try store.save(OfflinePage(topic: topic, page: 1, title: "Sujet", html: "<p>Bonjour</p>", savedAt: .now))
            let one = CacheStorageSnapshot.measure(cachesDirectory: caches, cache: cache)
            #expect(one.htmlFileCount == 1)
            #expect(one.htmlBytes > 0)
            try store.save(OfflinePage(topic: topic, page: 2, title: "Sujet", html: "<p>Suite</p>", savedAt: .now))
            #expect(CacheStorageSnapshot.measure(cachesDirectory: caches, cache: cache).htmlFileCount == 2)
        }
    }

    @Test func savedPagesAreCountedAndTheTotalCoversEveryFolder() throws {
        try withCaches { caches, cache, offline in
            try write(5_000, to: offline.appending(path: "13-1711/1.json"))
            try write(6_000, to: offline.appending(path: "13-1711/2.json"))
            try write(4_000, to: offline.appending(path: "25-99/1.json"))
            try write(7_000, to: caches.appending(path: "cache/avatars/x.png"))
            try write(8_000, to: caches.appending(path: "com.apple.other/y.bin"))
            let snapshot = CacheStorageSnapshot.measure(cachesDirectory: caches, cache: cache)
            #expect(snapshot.htmlFileCount == 3)
            #expect(snapshot.htmlBytes >= 15_000)
            #expect(snapshot.totalBytes >= snapshot.htmlBytes + 15_000)
            #expect(snapshot.totalBytes > snapshot.htmlBytes)
        }
    }

    @Test func onlyJSONFilesOfTopicFoldersCountAsSavedPages() throws {
        try withCaches { caches, cache, offline in
            try write(1_000, to: offline.appending(path: "13-1/1.json"))
            try write(1_000, to: offline.appending(path: "13-1/notes.txt"))
            try write(1_000, to: offline.appending(path: "13-1/.2.json"))
            try write(1_000, to: offline.appending(path: "13-1/deeper/3.json"))
            try write(1_000, to: offline.appending(path: "stray.json"))
            try write(1_000, to: offline.appending(path: ".hidden/4.json"))
            try write(1_000, to: offline.appending(path: "abc-def/1.json"))
            try write(1_000, to: offline.appending(path: "13-1-2/1.json"))
            try write(1_000, to: offline.appending(path: "013-1/1.json"))
            try write(1_000, to: offline.appending(path: "13-1/abc.json"))
            try write(1_000, to: offline.appending(path: "13-1/01.json"))
            try write(1_000, to: offline.appending(path: "13-1/7.JSON"))
            #expect(CacheStorageSnapshot.measure(cachesDirectory: caches, cache: cache).htmlFileCount == 1)
        }
    }

    @Test func theOldTopicPagesAreNotSavedPages() throws {
        try withCaches { caches, cache, _ in
            try write(1_000, to: caches.appending(path: "cache/pages/topic-A.htm"))
            try write(1_000, to: caches.appending(path: "cache/topic-B.htm"))
            let snapshot = CacheStorageSnapshot.measure(cachesDirectory: caches, cache: cache)
            #expect(snapshot.htmlFileCount == 0)
            #expect(snapshot.htmlBytes == 0)
            #expect(snapshot.totalBytes > 0)
        }
    }

    @Test func hiddenFilesAndFoldersAreLeftOutOfTheTotal() throws {
        try withCaches { caches, cache, _ in
            let visible = CacheStorageSnapshot.measure(cachesDirectory: caches, cache: cache).totalBytes
            try write(50_000, to: caches.appending(path: ".hidden-file"))
            try write(50_000, to: caches.appending(path: ".hidden-folder/inside.bin"))
            #expect(CacheStorageSnapshot.measure(cachesDirectory: caches, cache: cache).totalBytes == visible)
        }
    }

    @Test func aFolderNamedLikeAPageIsNotCounted() throws {
        try withCaches { caches, cache, offline in
            try FileManager.default.createDirectory(
                at: offline.appending(path: "13-1/1.json", directoryHint: .isDirectory), withIntermediateDirectories: true
            )
            #expect(CacheStorageSnapshot.measure(cachesDirectory: caches, cache: cache).htmlFileCount == 0)
        }
    }

    @Test func aSymbolicLinkIsNotFollowed() throws {
        try withCaches { caches, cache, offline in
            let outside = URL.temporaryDirectory.appending(path: "lot179-out-\(UUID().uuidString)", directoryHint: .isDirectory)
            try write(100_000, to: outside.appending(path: "1.json"))
            defer { try? FileManager.default.removeItem(at: outside) }
            let fileManager = FileManager.default
            try write(1_000, to: offline.appending(path: "13-1/1.json"))
            try fileManager.createSymbolicLink(
                at: offline.appending(path: "13-1/2.json"), withDestinationURL: outside.appending(path: "1.json")
            )
            try fileManager.createSymbolicLink(at: offline.appending(path: "25-2"), withDestinationURL: outside)
            try fileManager.createSymbolicLink(at: caches.appending(path: "linked"), withDestinationURL: outside)
            let snapshot = CacheStorageSnapshot.measure(cachesDirectory: caches, cache: cache)
            #expect(snapshot.htmlFileCount == 1)
            #expect(snapshot.htmlBytes < 100_000)
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

    @Test func theFooterStatesTheRuleOfTheSavedPages() {
        #expect(CacheStorageText.purgeRule()
            == "Les pages HTML enregistrées sont conservées quel que soit leur âge. Leur cache est limité à 200 Mo.")
        #expect(CacheStorageText.purgeRule(for: .topicPages)
            == "Les pages HTML de plus d’un jour sont supprimées automatiquement. Leur cache est limité à 20 Mo.")
        let legacy = CacheEvictionPolicy(maximumAge: 7 * 86_400, maximumTotalBytes: 50_000_000)
        #expect(CacheStorageText.purgeRule(for: legacy)
            == "Les pages HTML de plus de 7 jours sont supprimées automatiquement. Leur cache est limité à 50 Mo.")
    }
}
