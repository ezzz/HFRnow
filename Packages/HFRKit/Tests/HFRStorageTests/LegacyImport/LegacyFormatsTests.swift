import Foundation
import HFRModels
@testable import HFRStorage
import Testing

@Suite("Legacy formats (LOT-067)")
struct LegacyFormatsTests {
    private func defaults(_ name: String) throws -> InMemoryLegacyDefaults {
        InMemoryLegacyDefaults(plist: try LegacySamples.data(name))
    }

    // MARK: Super-favourites and sections (UserDefaults arrays)

    @Test("super-favourites read as legacy's loader: sorted, unique, above 0", arguments: [
        ("defaults-typical.plist", [12, 99, 3_050_500, 4_100_000]),
        ("defaults-boundary.plist", [1, 2_000_000, 2_147_483_647]),
        ("defaults-objc-insertion-order.plist", [12, 99, 3_050_500, 4_100_000]),
        ("defaults-same-number-two-categories.plist", [777]),
        ("defaults-empty.plist", []),
        ("defaults-absent.plist", [])
    ])
    func superFavorites(sample: String, expected: [Int]) throws {
        let value = try defaults(sample).value(forKey: LegacyKeys.superFavorites)
        #expect(LegacyFormats.superFavoriteNumbers(value) == expected)
    }

    @Test("super-favourites: numeric strings, booleans and reals read as NSNumber.intValue; 0, negatives, junk dropped")
    func superFavoritesTolerantValues() {
        let value = LegacyValue.array([
            .string("42"), .integer(42), .real(7.9), .bool(true), .integer(0), .integer(-3), .string("x"), .data(Data())
        ])
        #expect(LegacyFormats.superFavoriteNumbers(value) == [1, 7, 42])
        #expect(LegacyFormats.superFavoriteNumbers(.string("12")).isEmpty)
    }

    @Test("collapsed sections: trimmed, empty dropped, the whole array ignored when one element is not a string")
    func collapsedSections() throws {
        let boundary = try defaults("defaults-boundary.plist").value(forKey: LegacyKeys.collapsedSections)
        #expect(LegacyFormats.collapsedSections(boundary) == [
            "favorite-first-post:2000001", "favorite-order:2", "favorite-unknown", "forum-id:13",
            "forum-title:jeux vidéo", "forum-url:/forum1.php?config=hfr.inc&cat=25"
        ])
        #expect(LegacyFormats.collapsedSections(.array([.string(" a "), .string("  "), .string("a")])) == ["a"])
        #expect(LegacyFormats.collapsedSections(.array([.string("a"), .integer(1)])).isEmpty)
    }

    // MARK: Search history (JSON Data in UserDefaults)

    @Test("search history decodes the legacy JSON with counts and dates")
    func searchHistory() throws {
        let value = try defaults("defaults-search-history-typical.plist").value(forKey: LegacyKeys.smileySearchHistory)
        let entries = try #require(LegacyFormats.searchHistory(value))
        #expect(entries.map(\.text) == ["chat", "Chien", "rire", "Éclair"])
        #expect(entries.map(\.count) == [3, 1, 1, 1])
        #expect(entries[0].lastSearchedAt == Date(timeIntervalSinceReferenceDate: 725_760_060))
        let fifty = try defaults("defaults-search-history-50-entries.plist").value(forKey: LegacyKeys.smileySearchHistory)
        #expect(LegacyFormats.searchHistory(fifty)?.count == 50)
    }

    @Test("search history that does not decode reads as nothing, as legacy's try?")
    func searchHistoryCorrupt() throws {
        #expect(LegacyFormats.searchHistory(.data(try LegacySamples.data("search-history-corrupt-before.bin"))) == nil)
        #expect(LegacyFormats.searchHistory(.string("[]")) == nil)
        #expect(try defaults("defaults-search-history-absent.plist").value(forKey: LegacyKeys.smileySearchHistory) == nil)
    }

    // MARK: Upload history (JSON file)

    @Test("upload history keeps the legacy order, fields and exact instants")
    func uploadHistory() throws {
        let images = try #require(LegacyFormats.uploadHistory(try LegacySamples.data("upload-history-typical.json")))
        #expect(images.count == 3)
        #expect(images.map(\.uploadedAt) == images.map(\.uploadedAt).sorted(by: >))
        #expect(images[0].fullURL.absoluteString == "https://img3.super-h.fr/images/2024/01/01/c3d4e5f6a7b8.jpg")
        #expect(images[0].mediumURL?.absoluteString == "https://img3.super-h.fr/images/2024/01/01/c3d4e5f6a7b8.md.jpg")
        #expect(images[0].width == 1600 && images[0].height == 1200)
        let boundary = try #require(LegacyFormats.uploadHistory(try LegacySamples.data("upload-history-boundary.json")))
        #expect(boundary.count == 4)
        #expect(boundary[0].uploadedAt == Date(timeIntervalSinceReferenceDate: 725_760_000.1229999))
        #expect(boundary[0].mediumURL == nil && boundary[0].width == nil)
        #expect(LegacyFormats.uploadHistory(try LegacySamples.data("upload-history-empty.json")) == [])
        #expect(LegacyFormats.uploadHistory(try LegacySamples.data("upload-history-corrupt-before.bin")) == nil)
    }

    // MARK: Smiley favourites (NSKeyedArchiver, binary plist)

    /// Expected values read from the same archives by Python's `plistlib` (an independent decoder of the format).
    @Test("smiley favourites decode as an independent reader of the archive does, oldest first")
    func smileyFavorites() throws {
        func favorite(_ time: TimeInterval, _ code: String, _ url: String) -> LegacySmileyFavorite {
            LegacySmileyFavorite(code: code, url: url, addedAt: Date(timeIntervalSinceReferenceDate: time))
        }
        let base = "https://forum-images.hardware.fr/images/perso/"
        #expect(LegacyFormats.smileyFavorites(try LegacySamples.data("smiley-favorites-empty.archive")) == [])
        #expect(LegacyFormats.smileyFavorites(try LegacySamples.data("smiley-favorites-typical.archive")) == [
            favorite(725_760_000, "[:fake1]", base + "fake1.gif"),
            favorite(725_760_060, "[:fake2]", base + "fake2.gif"),
            favorite(725_760_120, "[:fake3:2]", base + "fake3.gif")
        ])
        #expect(LegacyFormats.smileyFavorites(try LegacySamples.data("smiley-favorites-boundary.archive")) == [
            favorite(725_673_600, "[:old]", base + "old.gif"),
            favorite(725_760_000, "[:Exemple]", base + "Exemple.gif"),
            favorite(725_760_000, "[:exemple]", base + "exemple.gif"),
            favorite(725_760_000.5, "[:\u{FC}n\u{EF}]", "https://example.invalid/a b/\u{FC}.gif?x=1&y=2")
        ])
    }

    @Test("a file that is not a keyed archive reads as nothing")
    func smileyFavoritesNotArchive() throws {
        #expect(LegacyFormats.smileyFavorites(Data("bplist00".utf8)) == nil)
        #expect(LegacyFormats.smileyFavorites(try LegacySamples.data("smiley-favorites-typical.xml.plist")) == nil)
        #expect(LegacyFormats.smileyFavorites(try LegacySamples.data("upload-history-typical.json")) == nil)
        var truncated = try LegacySamples.data("smiley-favorites-typical.archive")
        truncated.removeLast(40)
        #expect(LegacyFormats.smileyFavorites(truncated) == nil)
    }

    // MARK: Pseudo lists and drafts

    @Test("blocklist dictionary and allowlist entries keep the word, in order")
    func pseudoLists() throws {
        let dico = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>FakeUser1</key><array>
        <dict><key>alias</key><string></string><key>mode</key><integer>0</integer><key>word</key><string>fakeblocked1</string></dict>
        <dict><key>mode</key><integer>0</integer><key>word</key><string>fake\u{200B}blocked2</string></dict>
        <dict><key>alias</key><string></string></dict>
        </array></dict></plist>
        """
        let lists = try #require(LegacyFormats.blocklists(LegacyValue.parse(Data(dico.utf8))))
        #expect(lists == ["FakeUser1": ["fakeblocked1", "fake\u{200B}blocked2"]])
        #expect(LegacyFormats.blocklists(.array([])) == nil)
        #expect(LegacyFormats.pseudoList(.dictionary([:])) == nil)
    }

    @Test("active drafts: post-<n> ids only, blank texts dropped")
    func activeDrafts() throws {
        let value = LegacyValue.data(try Self.activeDraftsJSON([
            ActiveDraftFixture("post-123", "Bonjour", 725_760_000), ActiveDraftFixture("post-0", "zero", 1),
            ActiveDraftFixture("topic-5", "other", 1), ActiveDraftFixture("post-77", "  \n", 1),
            ActiveDraftFixture("post-9", "neuf", 725_760_100)
        ]))
        let drafts = try #require(LegacyFormats.activeDrafts(value))
        #expect(drafts == [
            LegacyActiveDraft(topicNumber: 123, text: "Bonjour", updatedAt: Date(timeIntervalSinceReferenceDate: 725_760_000)),
            LegacyActiveDraft(topicNumber: 9, text: "neuf", updatedAt: Date(timeIntervalSinceReferenceDate: 725_760_100))
        ])
        #expect(LegacyFormats.activeDrafts(.data(Data("{".utf8))) == nil)
    }

    // MARK: Helpers

    /// The legacy writer's shape (`ReplyDraftStore.ActiveDraftItem`, `AnswerView.swift:143-148`), `JSONEncoder` defaults.
    static func activeDraftsJSON(_ items: [ActiveDraftFixture]) throws -> Data {
        struct Item: Encodable {
            let topicID: String
            let topicTitle: String
            let text: String
            let updatedAt: Date
        }
        return try JSONEncoder().encode(items.map {
            Item(topicID: $0.topicID, topicTitle: "Titre", text: $0.text, updatedAt: Date(timeIntervalSinceReferenceDate: $0.time))
        })
    }
}

/// One legacy active draft for `activeDraftsJSON`.
struct ActiveDraftFixture {
    let topicID: String
    let text: String
    let time: TimeInterval

    init(_ topicID: String, _ text: String, _ time: TimeInterval) {
        self.topicID = topicID
        self.text = text
        self.time = time
    }
}

@Suite("Binary property list reader (LOT-067)")
struct BinaryPropertyListTests {
    /// A `bplist00` whose array `i` lists array `i + 1` `fanOut` times (the last one empty): a few hundred bytes that a
    /// reader without a node budget reads `fanOut^levels` times.
    private func sharedReferenceGraph(levels: Int, fanOut: Int) -> Data {
        var bytes = Array("bplist00".utf8)
        var offsets: [Int] = []
        for level in 0..<levels {
            offsets.append(bytes.count)
            let count = level == levels - 1 ? 0 : fanOut
            bytes.append(0xA0 | UInt8(count))
            bytes += Array(repeating: UInt8(level + 1), count: count)
        }
        let table = bytes.count
        for offset in offsets { bytes += [UInt8(offset >> 8), UInt8(offset & 0xFF)] }
        bytes += [0, 0, 0, 0, 0, 0, 2, 1]
        for value in [levels, 0, table] {
            bytes += (0..<8).reversed().map { UInt8((value >> ($0 * 8)) & 0xFF) }
        }
        return Data(bytes)
    }

    @Test("a small file of shared references is refused instead of being read exponentially")
    func nodeBudget() {
        // 4^12 = 16 777 216 reads without the budget, far above `maximumNodes`.
        #expect(throws: BinaryPlistError.malformed) { try BinaryPropertyList.parse(sharedReferenceGraph(levels: 13, fanOut: 4)) }
        #expect(throws: Never.self) { try BinaryPropertyList.parse(sharedReferenceGraph(levels: 4, fanOut: 3)) }
    }
}
