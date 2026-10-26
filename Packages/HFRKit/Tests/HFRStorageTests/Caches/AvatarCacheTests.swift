import Foundation
import Testing
@testable import HFRStorage

@Suite struct AvatarCacheTests {
    @Test func storedAvatarComesBackFresh() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let avatars = AvatarCache(cache: temp.cache)
        let url = try avatars.store(Data([1, 2, 3]), forPseudo: "Marc")
        let entry = try #require(try avatars.entry(forPseudo: "Marc"))
        #expect(entry.fileURL == url)
        #expect(entry.isFresh)
        #expect(try Data(contentsOf: entry.fileURL) == Data([1, 2, 3]))
        #expect(url.deletingLastPathComponent() == temp.cache.url(for: .avatars))
    }

    @Test func keyIgnoresCaseAndZeroWidthSpaces() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let avatars = AvatarCache(cache: temp.cache)
        try avatars.store(Data([9]), forPseudo: "Ma\u{200B}RC")
        #expect(try avatars.entry(forPseudo: "marc") != nil)
    }

    @Test func differentPseudosNeverShareAFile() throws {
        #expect(try AvatarCache.fileName(forPseudo: "ab") != AvatarCache.fileName(forPseudo: "ba"))
        #expect(try AvatarCache.fileName(forPseudo: "a") != AvatarCache.fileName(forPseudo: "a "))
    }

    @Test func fileNamesAreSafeForTheFileSystem() throws {
        for pseudo in ["../../etc/passwd", "a/b", "C:\\x", "é🙂", "nul\u{0}x", String(repeating: "z", count: 100)] {
            let name = try AvatarCache.fileName(forPseudo: pseudo)
            #expect(name.allSatisfy { "0123456789abcdef".contains($0) })
            #expect(name.count <= 255)
        }
    }

    @Test func staleAfterTwentyFourHoursButStillReturned() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let avatars = AvatarCache(cache: temp.cache)
        let url = try avatars.store(Data([1]), forPseudo: "Marc")
        let storedAt = Date(timeIntervalSince1970: 1_761_000_000)
        try FileManager.default.setAttributes([.modificationDate: storedAt], ofItemAtPath: url.path())
        let justInside = try #require(try avatars.entry(forPseudo: "Marc", now: storedAt.addingTimeInterval(86_400)))
        let justOutside = try #require(try avatars.entry(forPseudo: "Marc", now: storedAt.addingTimeInterval(86_401)))
        #expect(justInside.isFresh)
        #expect(!justOutside.isFresh)
        #expect(justOutside.storedAt == storedAt)
    }

    @Test func failedRefreshKeepsTheValidStaleFile() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let avatars = AvatarCache(cache: temp.cache)
        try avatars.store(Data([7, 7]), forPseudo: "Marc")
        #expect(throws: CacheError.emptyData) { try avatars.store(Data(), forPseudo: "Marc") }
        #expect(try Data(contentsOf: try #require(try avatars.entry(forPseudo: "Marc")).fileURL) == Data([7, 7]))
    }

    @Test func storeReplacesThePreviousFileWithoutLeavingTemporaries() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let avatars = AvatarCache(cache: temp.cache)
        try avatars.store(Data([1]), forPseudo: "Marc")
        try avatars.store(Data([2, 2]), forPseudo: "Marc")
        #expect(try Data(contentsOf: try #require(try avatars.entry(forPseudo: "Marc")).fileURL) == Data([2, 2]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: temp.cache.url(for: .avatars).path()).count == 1)
    }

    @Test func missingAvatarIsNilAndRemoveReportsIt() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let avatars = AvatarCache(cache: temp.cache)
        #expect(try avatars.entry(forPseudo: "ghost") == nil)
        #expect(try !avatars.remove(forPseudo: "ghost"))
        try avatars.store(Data([1]), forPseudo: "ghost")
        #expect(try avatars.remove(forPseudo: "GHOST"))
        #expect(try avatars.entry(forPseudo: "ghost") == nil)
    }

    @Test func invalidKeysAreRejected() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let avatars = AvatarCache(cache: temp.cache)
        #expect(throws: CacheError.emptyKey) { try avatars.store(Data([1]), forPseudo: "\u{200B}") }
        #expect(throws: CacheError.keyTooLong) { try avatars.store(Data([1]), forPseudo: String(repeating: "x", count: 101)) }
        #expect(throws: CacheError.emptyKey) { try avatars.entry(forPseudo: "") }
    }

    @Test func legacyPruningRemovesOldAvatarsThroughEvictAll() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let now = Date(timeIntervalSince1970: 1_761_000_000)
        let avatars = AvatarCache(cache: temp.cache)
        let old = try avatars.store(Data([1]), forPseudo: "old")
        let recent = try avatars.store(Data([1]), forPseudo: "recent")
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-26 * 86_400)], ofItemAtPath: old.path())
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-86_400)], ofItemAtPath: recent.path())
        temp.cache.evictAll(now: now)
        #expect(try avatars.entry(forPseudo: "old") == nil)
        #expect(try avatars.entry(forPseudo: "recent", now: now) != nil)
    }
}
