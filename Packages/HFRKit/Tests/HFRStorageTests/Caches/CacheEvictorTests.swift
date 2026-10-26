import Foundation
import Testing
@testable import HFRStorage

@Suite struct CacheEvictorTests {
    private let now = Date(timeIntervalSince1970: 1_761_000_000)
    private let day: TimeInterval = 86_400

    @Test func removesFilesOlderThanTheMaximumAgeOnly() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let old = try temp.makeFile("old", in: .avatars, size: 5, age: 26 * day, now: now)
        let recent = try temp.makeFile("recent", in: .avatars, size: 7, age: 24 * day, now: now)
        let report = CacheEvictor.evict(directory: temp.cache.url(for: .avatars), policy: .avatars, now: now)
        #expect(!temp.exists(old))
        #expect(temp.exists(recent))
        #expect(report.removedFileCount == 1)
        #expect(report.removedBytes == 5)
        #expect(report.remainingBytes == 7)
        #expect(report.failures.isEmpty)
    }

    @Test func fileExactlyAtTheMaximumAgeIsKept() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let edge = try temp.makeFile("edge", in: .avatars, age: 25 * day, now: now)
        CacheEvictor.evict(directory: temp.cache.url(for: .avatars), policy: .avatars, now: now)
        #expect(temp.exists(edge))
    }

    @Test func sizeBoundRemovesTheOldestFirstUntilItFits() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let oldest = try temp.makeFile("a", in: .avatars, size: 40, age: 3 * day, now: now)
        let middle = try temp.makeFile("b", in: .avatars, size: 40, age: 2 * day, now: now)
        let newest = try temp.makeFile("c", in: .avatars, size: 40, age: 1 * day, now: now)
        let report = CacheEvictor.evict(
            directory: temp.cache.url(for: .avatars), policy: CacheEvictionPolicy(maximumTotalBytes: 90), now: now
        )
        #expect(!temp.exists(oldest))
        #expect(temp.exists(middle))
        #expect(temp.exists(newest))
        #expect(report.removedFileCount == 1)
        #expect(report.remainingBytes == 80)
    }

    @Test func sizeBoundCountsOnlyWhatAgeRulesLeft() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let expired = try temp.makeFile("expired", in: .avatars, size: 100, age: 10 * day, now: now)
        let kept = try temp.makeFile("kept", in: .avatars, size: 100, age: 1 * day, now: now)
        CacheEvictor.evict(
            directory: temp.cache.url(for: .avatars), policy: CacheEvictionPolicy(maximumAge: 5 * day, maximumTotalBytes: 100), now: now
        )
        #expect(!temp.exists(expired))
        #expect(temp.exists(kept))
    }

    @Test func noPolicyLimitsKeepsEverything() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let file = try temp.makeFile("f", in: .avatars, age: 1000 * day, now: now)
        let report = CacheEvictor.evict(directory: temp.cache.url(for: .avatars), policy: CacheEvictionPolicy(), now: now)
        #expect(temp.exists(file))
        #expect(report.removedFileCount == 0)
    }

    @Test func missingDirectoryIsAnEmptyCache() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let report = CacheEvictor.evict(directory: temp.cache.url(for: .avatars), policy: .avatars, now: now)
        #expect(report == CacheEvictionReport())
    }

    @Test func recursesIntoSubfoldersButNeverRemovesFolders() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let directory = try temp.cache.prepare(.avatars)
        let nested = directory.appending(path: "sub/deeper", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let file = nested.appending(path: "x")
        try Data(count: 3).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-30 * day)], ofItemAtPath: file.path())
        CacheEvictor.evict(directory: directory, policy: .avatars, now: now)
        #expect(!temp.exists(file))
        #expect(temp.exists(nested))
    }

    @Test func symbolicLinksAreNeitherFollowedNorCounted() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let outside = temp.base.appending(path: "outside.bin")
        try Data(count: 500).write(to: outside)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-90 * day)], ofItemAtPath: outside.path())
        let directory = try temp.cache.prepare(.avatars)
        try FileManager.default.createSymbolicLink(at: directory.appending(path: "link"), withDestinationURL: outside)
        let report = CacheEvictor.evict(directory: directory, policy: .avatars, now: now)
        #expect(temp.exists(outside))
        #expect(report.removedFileCount == 0)
        #expect(report.remainingBytes == 0)
    }

    @Test func evictAllAppliesEachAreasOwnPolicy() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let page = try temp.makeFile("p.htm", in: .topicPages, age: 2 * day, now: now)
        let avatar = try temp.makeFile("a", in: .avatars, age: 2 * day, now: now)
        let reports = temp.cache.evictAll(now: now)
        #expect(!temp.exists(page))
        #expect(temp.exists(avatar))
        #expect(reports[.topicPages]?.removedFileCount == 1)
        #expect(reports[.avatars]?.removedFileCount == 0)
    }

    @Test func clearEmptiesAnAreaAndKeepsTheOthers() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let avatar = try temp.makeFile("a", in: .avatars, size: 4, age: 0, now: .now)
        let page = try temp.makeFile("p", in: .topicPages, size: 6, age: 0, now: .now)
        let report = temp.cache.clear(.avatars)
        #expect(!temp.exists(avatar))
        #expect(temp.exists(page))
        #expect(report.removedBytes == 4)
        #expect(temp.cache.size(of: .avatars) == 0)
        #expect(temp.cache.size(of: .topicPages) == 6)
    }

    @Test func clearRemovesFutureDatedFilesToo() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let future = try temp.makeFile("future", in: .avatars, size: 5, age: -3 * day, now: .now)
        let report = temp.cache.clear(.avatars)
        #expect(!temp.exists(future))
        #expect(report.removedFileCount == 1)
    }

    @Test func manyExpiredFilesAreAllRemoved() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        for index in 0..<300 { try temp.makeFile("old\(index)", in: .avatars, size: 1, age: 40 * day, now: now) }
        let kept = try temp.makeFile("kept", in: .avatars, size: 1, age: day, now: now)
        let report = CacheEvictor.evict(directory: temp.cache.url(for: .avatars), policy: .avatars, now: now)
        #expect(report.removedFileCount == 300)
        #expect(temp.exists(kept))
    }

    @Test func expiredFilesThatCannotBeRemovedStillCountTowardsTheSizeBound() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let stuck = try temp.makeFile("stuck", in: .avatars, size: 60, age: 10 * day, now: now)
        let older = try temp.makeFile("older", in: .avatars, size: 30, age: 2 * day, now: now)
        let newer = try temp.makeFile("newer", in: .avatars, size: 30, age: 1 * day, now: now)
        struct Refused: Error {}
        let report = CacheEvictor.evict(
            directory: temp.cache.url(for: .avatars),
            policy: CacheEvictionPolicy(maximumAge: 5 * day, maximumTotalBytes: 100),
            now: now,
            removeFile: { url in
                if url.lastPathComponent == "stuck" { throw Refused() }
                try FileManager.default.removeItem(at: url)
            }
        )
        #expect(temp.exists(stuck))
        #expect(!temp.exists(older))
        #expect(temp.exists(newer))
        #expect(report.failures.count == 1)
        #expect(report.remainingBytes == 90)
    }

    @Test func aSymbolicLinkAsTheAreaFolderIsIgnoredAndReported() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let outside = temp.base.appending(path: "outside", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let victim = outside.appending(path: "victim")
        try Data(count: 4).write(to: victim)
        try FileManager.default.createDirectory(at: temp.cache.root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: temp.cache.url(for: .avatars), withDestinationURL: outside)
        let report = temp.cache.clear(.avatars)
        #expect(temp.exists(victim))
        #expect(report.removedFileCount == 0)
        #expect(report.failures.count == 1)
    }

    @Test func clearRemovesEmptyFiles() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let empty = try temp.makeFile("empty", in: .topicPages, size: 0, age: 0, now: .now)
        let report = temp.cache.clear(.topicPages)
        #expect(!temp.exists(empty))
        #expect(report.removedFileCount == 1)
    }

    @Test func aSymbolicLinkAsTheCacheRootIsNeverTraversed() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let realRoot = temp.base.appending(path: "real", directoryHint: .isDirectory)
        let victimArea = realRoot.appending(path: "avatars", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: victimArea, withIntermediateDirectories: true)
        let victim = victimArea.appending(path: "victim")
        try Data(count: 4).write(to: victim)
        let linked = CacheDirectory(root: temp.base.appending(path: "linked"))
        try FileManager.default.createSymbolicLink(at: linked.root, withDestinationURL: realRoot)
        #expect(throws: CacheError.unsafeFolder) { try linked.safeURL(for: .avatars) }
        #expect(throws: CacheError.unsafeFolder) { try linked.prepare(.topicPages) }
        linked.clear(.avatars)
        linked.evictAll(now: .distantFuture)
        #expect(temp.exists(victim))
        #expect(linked.size(of: .avatars) == 0)
        #expect(linked.clear(.avatars).failures.count == 1)
    }

    @Test func aSymbolicLinkAsAnAreaIsRejectedByEveryEntryPoint() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let outside = temp.base.appending(path: "outside", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temp.cache.root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: temp.cache.url(for: .avatars), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: temp.cache.url(for: .topicPages), withDestinationURL: outside)
        #expect(throws: CacheError.unsafeFolder) { try AvatarCache(cache: temp.cache).store(Data([1]), forPseudo: "marc") }
        #expect(throws: CacheError.unsafeFolder) { try TemporaryFileCache(cache: temp.cache).write("x") }
        #expect(throws: CacheError.unsafeFolder) { try AvatarCache(cache: temp.cache).entry(forPseudo: "marc") }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path()).isEmpty)
    }

    @Test func aSymbolicLinkedFileInsideAnAreaSurvivesClear() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let outside = temp.base.appending(path: "outside.bin")
        try Data(count: 4).write(to: outside)
        let directory = try temp.cache.prepare(.avatars)
        try FileManager.default.createSymbolicLink(at: directory.appending(path: "link"), withDestinationURL: outside)
        temp.cache.clear(.avatars)
        #expect(temp.exists(outside))
    }
}
