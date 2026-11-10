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

/// #714: the avatar files the legacy app cached, named `MD5(lowercased pseudo)`, are adopted under the SwiftHFR name.
@Suite struct LegacyAvatarAdoptionTests {
    /// RFC 1321 appendix A.5 vectors.
    @Test("MD5 follows RFC 1321", arguments: [
        ("", "d41d8cd98f00b204e9800998ecf8427e"),
        ("a", "0cc175b9c0f1b6a831c399e269772661"),
        ("abc", "900150983cd24fb0d6963f7d28e17f72"),
        ("message digest", "f96b697d7cb7938d525a2f31aaf161d0"),
        ("abcdefghijklmnopqrstuvwxyz", "c3fcd3d76192e4007dfb496cca67e13b"),
        (String(repeating: "1234567890", count: 8), "57edf4a22be3c955ac49da2e2107b67a")
    ])
    func md5Vectors(input: String, digest: String) {
        #expect(LegacyAvatarName.hex(LegacyAvatarName.md5(Array(input.utf8))) == digest)
    }

    @Test func legacyNameLowercasesAndTriesBothSpellingsOfAZeroWidthSpace() {
        #expect(LegacyAvatarName.candidates(forPseudo: "ABC") == ["900150983cd24fb0d6963f7d28e17f72"])
        #expect(LegacyAvatarName.candidates(forPseudo: "A\u{200B}bc").count == 2)
        #expect(LegacyAvatarName.candidates(forPseudo: "A\u{200B}bc").last == "900150983cd24fb0d6963f7d28e17f72")
    }

    private func legacyFile(_ temp: TemporaryCache, pseudo: String, bytes: Data) throws -> URL {
        let directory = try temp.cache.prepare(.avatars)
        let url = directory.appending(path: try #require(LegacyAvatarName.candidates(forPseudo: pseudo).first), directoryHint: .notDirectory)
        try bytes.write(to: url)
        return url
    }

    @Test func adoptsTheLegacyFileUnderTheSwiftHFRNameAndKeepsTheLegacyOne() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let legacy = try legacyFile(temp, pseudo: "Marc", bytes: Data([4, 2]))
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: legacy.path())
        let avatars = AvatarCache(cache: temp.cache)
        #expect(try avatars.entry(forPseudo: "Marc") == nil)
        let entry = try #require(try avatars.entryAdoptingLegacy(forPseudo: "MARC", accepting: { _ in true }))
        #expect(try Data(contentsOf: entry.fileURL) == Data([4, 2]))
        #expect(entry.fileURL.lastPathComponent == (try AvatarCache.fileName(forPseudo: "marc")))
        // The legacy date is kept, so an old avatar is still fresh-checked by the pages; the legacy file is untouched.
        #expect(entry.storedAt == oldDate)
        #expect(!entry.isFresh)
        #expect(try Data(contentsOf: legacy) == Data([4, 2]))
        // Adopted once: the SwiftHFR file answers from now on.
        #expect(try avatars.entry(forPseudo: "Marc") != nil)
    }

    @Test func anExistingEntryWinsOverTheLegacyFile() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        _ = try legacyFile(temp, pseudo: "Marc", bytes: Data([1]))
        let avatars = AvatarCache(cache: temp.cache)
        try avatars.store(Data([2]), forPseudo: "Marc")
        let entry = try #require(try avatars.entryAdoptingLegacy(forPseudo: "Marc", accepting: { _ in true }))
        #expect(try Data(contentsOf: entry.fileURL) == Data([2]))
    }

    @Test func aLegacyNameWithAZeroWidthSpaceIsFound() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        // Legacy hashed the pseudo as printed, with the U+200B HFR puts in long pseudos.
        let url = try temp.cache.prepare(.avatars).appending(path: LegacyAvatarName.candidates(forPseudo: "A\u{200B}bc")[0], directoryHint: .notDirectory)
        try Data([5]).write(to: url)
        let avatars = AvatarCache(cache: temp.cache)
        #expect(try avatars.entryAdoptingLegacy(forPseudo: "A\u{200B}bc", accepting: { _ in true }) != nil)
    }

    @Test func refusesWhatIsNotAnAcceptableFile() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let avatars = AvatarCache(cache: temp.cache)
        // Bytes the caller does not accept (not an image), an empty file, a file over the cap, a missing one.
        _ = try legacyFile(temp, pseudo: "notimage", bytes: Data([1]))
        #expect(try avatars.entryAdoptingLegacy(forPseudo: "notimage", accepting: { _ in false }) == nil)
        _ = try legacyFile(temp, pseudo: "empty", bytes: Data())
        #expect(try avatars.entryAdoptingLegacy(forPseudo: "empty", accepting: { _ in true }) == nil)
        _ = try legacyFile(temp, pseudo: "big", bytes: Data(count: AvatarCache.legacyMaximumBytes + 1))
        #expect(try avatars.entryAdoptingLegacy(forPseudo: "big", accepting: { _ in true }) == nil)
        _ = try legacyFile(temp, pseudo: "limit", bytes: Data(repeating: 1, count: AvatarCache.legacyMaximumBytes))
        #expect(try avatars.entryAdoptingLegacy(forPseudo: "limit", accepting: { _ in true }) != nil)
        #expect(try avatars.entryAdoptingLegacy(forPseudo: "nobody", accepting: { _ in true }) == nil)
        #expect(try avatars.entry(forPseudo: "notimage") == nil && avatars.entry(forPseudo: "big") == nil)
    }

    @Test func neverFollowsASymbolicLinkOrReadsADirectory() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let directory = try temp.cache.prepare(.avatars)
        let secret = temp.cache.root.appending(path: "outside.bin")
        try Data([9, 9]).write(to: secret)
        let linkName = try #require(LegacyAvatarName.candidates(forPseudo: "linked").first)
        try FileManager.default.createSymbolicLink(at: directory.appending(path: linkName), withDestinationURL: secret)
        let folderName = try #require(LegacyAvatarName.candidates(forPseudo: "folder").first)
        try FileManager.default.createDirectory(at: directory.appending(path: folderName), withIntermediateDirectories: false)
        let avatars = AvatarCache(cache: temp.cache)
        #expect(try avatars.entryAdoptingLegacy(forPseudo: "linked", accepting: { _ in true }) == nil)
        #expect(try avatars.entryAdoptingLegacy(forPseudo: "folder", accepting: { _ in true }) == nil)
    }

    @Test func anUnsafeAvatarsFolderThrowsAsTheCacheDoes() throws {
        let temp = try TemporaryCache()
        defer { temp.cleanUp() }
        let elsewhere = temp.cache.root.deletingLastPathComponent().appending(path: "elsewhere-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        try FileManager.default.createDirectory(at: temp.cache.root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: temp.cache.url(for: .avatars), withDestinationURL: elsewhere)
        #expect(throws: CacheError.unsafeFolder) {
            try AvatarCache(cache: temp.cache).entryAdoptingLegacy(forPseudo: "x", accepting: { _ in true })
        }
    }
}
