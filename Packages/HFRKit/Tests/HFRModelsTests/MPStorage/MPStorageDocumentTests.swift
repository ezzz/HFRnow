import Foundation
import Testing
@testable import HFRModels

@Suite struct MPStorageDocumentTests {
    /// Shape of the real documents seen in the wild (audit E23), with numbers and strings mixed.
    private let wild = """
    {"data":[{"version":"0.1",
      "mpFlags":{"list":[{"post":123,"p":"1","href":"/h","page":4,"uri":"/u"}],"active":true},
      "blacklist":{},
      "bookmarks":{"list":[
        {"createDate":1700000000123,"post":"1711","author":"Bob","numreponse":55,"cat":"13","label":"L","color":"red"},
        {"createDate":"1700000000000","post":1712,"author":"Eve","numreponse":"56","cat":13,"label":"M"}],
        "sourceName":"iOS","lastUpdate":1700000000500},
      "hfrChat":{"x":[1,2,{"y":null}]},"superFavs":{},"sourceName":"DTCloud_GM","lastUpdate":1700000001000}],
     "sourceName":"DTCloud_GM","lastUpdate":1700000001000,"futureRootKey":"keep me"}
    """

    private func decode(_ text: String) throws -> MPStorageDocument {
        try JSONDecoder().decode(MPStorageDocument.self, from: Data(text.utf8))
    }

    @Test func decodesNumbersAndStringsInterchangeably() throws {
        let entry = try #require(try decode(wild).data.first)
        let bookmarks = try #require(entry.bookmarks?.list)
        #expect(bookmarks.map(\.topic) == [1711, 1712])
        #expect(bookmarks.map(\.numreponse) == [55, 56])
        #expect(bookmarks.map(\.category) == ["13", "13"])
        #expect(bookmarks[0].createdAt == Date(timeIntervalSince1970: 1_700_000_000.123))
        #expect(bookmarks[1].createdAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(entry.mpFlags?.list.first == MPStorageMPFlag(topic: 123, pValue: "1", href: "/h", page: 4, uri: "/u"))
    }

    @Test func emptyBlocklistObjectIsAnEmptySection() throws {
        let entry = try #require(try decode(wild).data.first)
        #expect(entry.blocklist?.list.isEmpty == true)
    }

    @Test func unknownNamespacesAndKeysSurviveARoundTrip() throws {
        let document = try decode(wild)
        let entry = try #require(document.data.first)
        #expect(entry.extra["hfrChat"] != nil)
        #expect(entry.extra["superFavs"] == .object([:]))
        #expect(entry.mpFlags?.extra["active"] == .bool(true))
        #expect(entry.bookmarks?.list.first?.extra["color"] == .string("red"))
        #expect(document.extra["futureRootKey"] == .string("keep me"))

        let again = try roundTrip(document)
        #expect(again == document)
        let reencoded = try JSONEncoder().encode(document)
        let output = try text(of: reencoded)
        #expect(output.contains("futureRootKey"))
        #expect(output.contains("hfrChat"))
        #expect(output.contains(#""color":"red""#))
    }

    @Test func writerMetadataIsKeptPerLevel() throws {
        let document = try decode(wild)
        let entry = try #require(document.data.first)
        #expect(document.sourceName == "DTCloud_GM")
        #expect(entry.sourceName == "DTCloud_GM")
        #expect(entry.bookmarks?.sourceName == "iOS")
        #expect(entry.bookmarks?.lastUpdate == Date(timeIntervalSince1970: 1_700_000_000.5))
        #expect(entry.version == "0.1")
    }

    @Test func millisecondDatesAreWrittenAsIntegers() throws {
        let document = MPStorageDocument(lastUpdate: Date(timeIntervalSince1970: 1_700_000_000.123))
        let output = try text(of: JSONEncoder().encode(document))
        #expect(output.contains(#""lastUpdate":1700000000123"#))
    }

    @Test(arguments: [1_700_000_000_001, 1_700_000_000_999, 1_234_567_890_123, 1_699_999_999_997])
    func everyMillisecondSurvivesARoundTrip(milliseconds: Int64) throws {
        let json = #"{"data":[],"lastUpdate":\#(milliseconds)}"#
        let document = try decode(json)
        let reencoded = try text(of: JSONEncoder().encode(document))
        #expect(reencoded.contains(#""lastUpdate":\#(milliseconds)"#))
    }

    @Test func bookmarkIsWrittenInTheLegacyShape() throws {
        let bookmark = MPStorageBookmark(topic: 1711, category: "13", numreponse: 55, author: "Bob", label: "L", createdAt: nil)
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(bookmark)) as? [String: Any]
        )
        #expect(object["post"] as? String == "1711")
        #expect(object["cat"] as? String == "13")
        #expect(object["numreponse"] as? Int == 55)
    }

    @Test func undecodableItemsAreKeptNotDropped() throws {
        let json = """
        {"data":[{"version":"0.1","bookmarks":{"list":[
        {"post":"x","cat":"1","numreponse":1},
        {"post":5,"cat":"2","numreponse":6,"author":"A","label":"B"}]}}]}
        """
        let document = try decode(json)
        let section = try #require(document.data.first?.bookmarks)
        #expect(section.list.count == 1)
        #expect(section.undecodableItems.count == 1)
        let reencoded = try text(of: JSONEncoder().encode(document))
        #expect(reencoded.contains(#""post":"x""#))
    }

    @Test func bookmarkIdentityIncludesTheCategory() {
        let first = MPStorageBookmark(topic: 1, category: "13", numreponse: 5, author: "", label: "")
        let second = MPStorageBookmark(topic: 1, category: "14", numreponse: 5, author: "", label: "")
        #expect(first.id != second.id)
        #expect(MPStorageMPFlag(topic: 9).id == 9)
    }

    @Test func missingDataKeyFailsInsteadOfResettingToDefault() {
        #expect(throws: DecodingError.self) { try decode(#"{"sourceName":"x"}"#) }
        #expect(throws: DecodingError.self) { try decode("[]") }
    }

    @Test func newDocumentHasOneEmptyVersionedEntry() {
        let document = MPStorageDocument()
        #expect(document.data.count == 1)
        #expect(document.data[0].version == "0.1")
        #expect(MPStorageDocument.subject == "a2bcc09b796b8c6fab77058ff8446c34")
        #expect(MPStorageDocument.recipient == "MultiMP")
    }

    @Test func blocklistEntryRequiresAUsernameAndKeepsExtraKeys() throws {
        let section = try JSONDecoder().decode(
            MPStorageSection<MPStorageBlocklistEntry>.self,
            from: Data(#"{"list":[{"username":"Troll","createDate":1000,"note":"n"},{"createDate":2}]}"#.utf8)
        )
        #expect(section.list.count == 1)
        #expect(section.list[0].username == "Troll")
        #expect(section.list[0].extra["note"] == .string("n"))
        #expect(section.undecodableItems.count == 1)
    }

    @Test func jsonValueRoundTripsEveryCase() throws {
        let value = JSONValue.object([
            "a": .null, "b": .bool(true), "c": .number(1.5), "d": .string("x"), "e": .array([.number(1), .null])
        ])
        #expect(try roundTrip(value) == value)
    }

    @Test(arguments: ["1e19", "\"nan\"", "\"inf\"", "\"-inf\"", "-1e19", "9e15"])
    func invalidTimestampsAreRejectedAtDecodeInsteadOfTrappingOnEncode(value: String) throws {
        #expect(throws: DecodingError.self) { try decode(#"{"data":[],"lastUpdate":\#(value)}"#) }
        let item = #"{"data":[{"bookmarks":{"list":[{"post":1,"cat":"1","numreponse":1,"createDate":\#(value)}]}}]}"#
        let section = try #require(try decode(item).data.first?.bookmarks)
        #expect(section.list.isEmpty)
        #expect(section.undecodableItems.count == 1)
        #expect(throws: Never.self) { try JSONEncoder().encode(try decode(item)) }
    }

    @Test(arguments: [Double.infinity, -Double.infinity, Double.nan, 1e300, 8_640_000_000_001, -8_640_000_000_001])
    func unrepresentableDatesThrowOnEncodeInsteadOfTrapping(seconds: Double) {
        // The document is built inside the closure: Foundation's Date.description itself traps on non-finite
        // dates on Linux, and the test framework would print a captured document.
        #expect(throws: EncodingError.self) {
            try JSONEncoder().encode(MPStorageDocument(lastUpdate: Date(timeIntervalSince1970: seconds)))
        }
    }

    @Test func extremeButValidTimestampsStillRoundTrip() throws {
        let document = try decode(#"{"data":[],"lastUpdate":8640000000000000}"#)
        #expect(try roundTrip(document) == document)
    }
}
