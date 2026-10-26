import Foundation
import Testing
@testable import HFRModels

@Suite struct MPStorageCodecTests {
    private typealias Fixtures = MPStorageFixtures

    @Test func writtenTextDecodesToTheSameDocumentWithEveryNamespace() throws {
        let document = try Fixtures.document()
        let text = try MPStorageCodec.encodeForWriting(document)
        #expect(try MPStorageCodec.decode(text) == document)
        for key in ["hfrChat", "superFavs", "futureRootKey", #""active":true"#, #""color":"red""#] {
            #expect(text.contains(key))
        }
    }

    @Test func outputIsCompactWithIntegersAndUnescapedSlashes() throws {
        let text = try MPStorageCodec.encodeForWriting(try Fixtures.document())
        #expect(!text.contains("\n") && !text.contains(": "))
        #expect(text.contains(#""x":[1,2,{"y":null}]"#))
        #expect(text.contains(#""href":"/h""#))
        #expect(text.contains(#""createDate":1700000000123"#))
    }

    @Test func nonBMPCharactersAnywhereAreRefusedWithTheirPath() throws {
        var document = try Fixtures.document()
        document.primary.extra["hfrChat"] = .object(["msg": .array([.string("ok"), .string("🎉")])])
        let error = try #require(throws: MPStorageError.self) { try MPStorageCodec.encodeForWriting(document) }
        #expect(error == .nonBMPCharacter(path: ".data[0].hfrChat.msg[1]", codePoint: 0x1F389))
    }

    @Test func aNonBMPKeyIsRefusedToo() throws {
        var document = try Fixtures.document()
        document.extra["🔑"] = .null
        let error = try #require(throws: MPStorageError.self) { try MPStorageCodec.encodeForWriting(document) }
        #expect(error == .nonBMPCharacter(path: ".<key>", codePoint: 0x1F511))
    }

    @Test func theSizeCapIsInclusive() throws {
        let document = try Fixtures.document()
        let size = try MPStorageCodec.encodeForWriting(document).utf8.count
        #expect(throws: Never.self) { try MPStorageCodec.encodeForWriting(document, limit: size) }
        #expect(throws: MPStorageError.tooLarge(byteCount: size, limit: size - 1)) {
            try MPStorageCodec.encodeForWriting(document, limit: size - 1)
        }
    }

    @Test func aDocumentAbove64KiBIsRefused() throws {
        var document = MPStorageDocument()
        for index in 0..<700 {
            let label = String(repeating: "x", count: 80)
            try document.addBookmark(Fixtures.bookmark(index, label: label), stamp: Fixtures.stamp(1_800_000_000))
        }
        let error = try #require(throws: MPStorageError.self) { try MPStorageCodec.encodeForWriting(document) }
        guard case let .tooLarge(byteCount, limit) = error else {
            Issue.record("Unexpected \(error)")
            return
        }
        #expect(limit == 65_536 && byteCount > limit)
    }

    @Test func aDocumentWithoutAVersion01EntryIsNeverWritten() throws {
        let document = try Fixtures.document(#"{"data":[{"version":"0.2"}]}"#)
        #expect(throws: MPStorageError.noWritableEntry) { try MPStorageCodec.encodeForWriting(document) }
    }

    @Test(arguments: [
        "", "{}", #"{"data":"#, "not json",
        // Truncated texts (HFR cuts long posts): never a crash.
        #"{"data":[{"version":"0.1","x":"abc\"#, #"{"data":[{"version":"0.1","x":"abc\u12"#,
        #"{"data":[{"version":"0.1","x":"abc"#, #"{"data":[{"version":"0.1","x":12"#, #"{"data":[{"version":"0.1","x":-"#, "\""
    ])
    func invalidTextThrowsInsteadOfResetting(text: String) {
        #expect(throws: (any Error).self) { try MPStorageCodec.decode(text) }
    }

    @Test func tombstonesRoundTripAndForeignValuesStayVerbatim() throws {
        let json = """
        {"data":[{"version":"0.1",
          "bookmarks":{"list":[],"tombstones":[{"id":"13-1-2","deleteDate":1800000000000,"by":"x"}]},
          "blacklist":{"list":[],"tombstones":[{"nope":1}]}}]}
        """
        let document = try Fixtures.document(json)
        #expect(document.primary.bookmarks?.tombstones.first?.id == "13-1-2")
        #expect(document.primary.bookmarks?.tombstones.first?.extra["by"] == .string("x"))
        #expect(document.primary.blocklist?.tombstones.isEmpty == true)
        #expect(document.primary.blocklist?.extra["tombstones"] == .array([.object(["nope": .number(1)])]))
        let text = try MPStorageCodec.encodeForWriting(document)
        #expect(try MPStorageCodec.decode(text) == document)
        #expect(text.contains(#""tombstones":[{"nope":1}]"#))
    }

    @Test func otherClientsNumbersAreWrittenBackByteForByte() throws {
        let numbers = #"{"big":9007199254740993,"exp":1e17,"list":[0,10.0],"negZero":-0.0,"padded":1.50,"small":-12E-3}"#
        let json = #"{"data":[{"version":"0.1","hfrChat":\#(numbers)}],"futureRoot":123456789012345678901}"#
        let document = try MPStorageCodec.decode(json)
        #expect(document.primary.extra["hfrChat"]?.member("big") == .number(try #require(JSONNumber(lexeme: "9007199254740993"))))
        let text = try MPStorageCodec.encodeForWriting(document)
        #expect(text.contains(numbers))
        #expect(text.contains(#""futureRoot":123456789012345678901"#))
        #expect(try MPStorageCodec.decode(text) == document)
    }

    @Test func modelledFieldsStillReadUnusualNumberSpellings() throws {
        let json = #"{"data":[{"version":"0.1","bookmarks":{"list":[{"post":1.711e3,"cat":13,"numreponse":5.6e1,"createDate":1.7e12}]}}]}"#
        let bookmark = try #require(try MPStorageCodec.decode(json).primary.bookmarks?.list.first)
        #expect(bookmark.topic == 1711 && bookmark.category == "13" && bookmark.numreponse == 56)
        #expect(bookmark.createdAt == Date(timeIntervalSince1970: 1.7e9))
    }

    @Test func numericLookingStringsStayStrings() throws {
        let document = try MPStorageCodec.decode(#"{"data":[{"version":"0.1","x":"123","y":"-0.0"}]}"#)
        #expect(document.primary.extra["x"] == .string("123"))
        let text = try MPStorageCodec.encodeForWriting(document)
        #expect(text.contains(#""x":"123""#) && text.contains(#""y":"-0.0""#))
    }

    @Test(arguments: [#""\ud83d""#, #""a\uDC00b""#, #""\ud83d\u0041""#, #"{"k\ud800":1}"#])
    func loneSurrogateEscapesAreReportedClearly(value: String) {
        let json = #"{"data":[{"version":"0.1","x":\#(value)}]}"#
        #expect {
            try MPStorageCodec.decode(json)
        } throws: { error in
            guard case MPStorageError.unpairedSurrogate = error else { return false }
            return true
        }
    }

    @Test func aPairedSurrogateEscapeDecodesAndIsThenRefusedForWriting() throws {
        let document = try MPStorageCodec.decode(#"{"data":[{"version":"0.1","x":"\ud83d\ude00"}]}"#)
        #expect(document.primary.extra["x"] == .string("😀"))
        #expect(throws: MPStorageError.nonBMPCharacter(path: ".data[0].x", codePoint: 0x1F600)) {
            try MPStorageCodec.encodeForWriting(document)
        }
    }

    @Test func aNonFiniteNumberIsAnEncodingErrorNotABrokenDocument() throws {
        var document = try Fixtures.document()
        document.extra["bad"] = .number(JSONNumber(Double.infinity))
        #expect(throws: EncodingError.self) { try MPStorageCodec.encodeForWriting(document) }
    }
}
