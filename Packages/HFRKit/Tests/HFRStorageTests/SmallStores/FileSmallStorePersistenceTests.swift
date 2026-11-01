import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// The JSON file under every small store.
@Suite struct FileSmallStorePersistenceTests {
    static let cuisine = TopicID(category: .forum(13), topic: 28563)

    @Test func missingFileLoadsAsNilWithoutCreatingAnything() throws {
        let directory = try SmallStoreTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "missing/superfavorites.json")
        let persistence = FileSmallStorePersistence<SuperFavoritesDocument>(fileURL: file)
        #expect(try persistence.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "missing").path(percentEncoded: false)))
    }

    @Test func theExactJSONHoldsIdsNumbersAndDatesAsSecondsSince2001() throws {
        let directory = try SmallStoreTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "superfavorites.json")
        let persistence = FileSmallStorePersistence<SuperFavoritesDocument>(fileURL: file)
        let favorite = SuperFavorite(topic: Self.cuisine, addedAt: Date(timeIntervalSinceReferenceDate: 800_000_000))
        try persistence.save(SuperFavoritesDocument(accounts: ["user1": [favorite]]))
        let json = String(bytes: try Data(contentsOf: file), encoding: .utf8)
        #expect(json == #"{"accounts":{"user1":[{"addedAt":800000000,"topic":{"category":"13","topic":28563}}]},"version":1}"#)
        let entries = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        #expect(entries == ["superfavorites.json"])
    }

    @Test func datesAndUploadIdentitiesComeBackExactly() throws {
        let directory = try SmallStoreTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = FileSmallStorePersistence<RehostUploadHistoryDocument>(fileURL: directory.appending(path: "uploads.json"))
        let images = try (0..<200).map { index in
            RehostedImage(
                fullURL: try #require(URL(string: "https://img.example/\(index).png")),
                uploadedAt: Date(timeIntervalSinceReferenceDate: 800_000_000.123_456_7 + Double(index) / 7)
            )
        }
        try persistence.save(RehostUploadHistoryDocument(images: images))
        let loaded = try #require(try persistence.load())
        #expect(loaded.images == images)
        #expect(loaded.images.map(\.id) == images.map(\.id))
    }

    @Test func aNewerVersionIsReportedEvenWhenItsShapeChanged() throws {
        let directory = try SmallStoreTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.json")
        try Data(#"{"version":2,"searches":{"chat":3}}"#.utf8).write(to: file)
        let persistence = FileSmallStorePersistence<SmileySearchHistoryDocument>(fileURL: file)
        #expect(throws: SmallStoreError.unsupportedVersion(2)) { try persistence.load() }
    }

    @Test(arguments: [0, -3])
    func aVersionBelowOneIsUnreadable(version: Int) throws {
        let directory = try SmallStoreTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.json")
        try Data(#"{"version":\#(version),"entries":[]}"#.utf8).write(to: file)
        #expect(throws: SmallStoreError.loadFailed(reason: "invalid version \(version)")) {
            try FileSmallStorePersistence<SmileySearchHistoryDocument>(fileURL: file).load()
        }
    }

    @Test(arguments: [#"{not json"#, #"{"entries":[]}"#, #"{"version":"1","entries":[]}"#, #"{"version":1}"#])
    func unreadableDataThrows(content: String) throws {
        let directory = try SmallStoreTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.json")
        try Data(content.utf8).write(to: file)
        #expect(throws: DecodingError.self) { try FileSmallStorePersistence<SmileySearchHistoryDocument>(fileURL: file).load() }
    }

    @Test func quarantineKeepsTheEarlierBackup() throws {
        let directory = try SmallStoreTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "layout.json")
        let persistence = FileSmallStorePersistence<FavoritesLayoutDocument>(fileURL: file)
        try Data("first".utf8).write(to: file)
        try persistence.quarantineUnreadableData()
        try Data("second".utf8).write(to: file)
        try persistence.quarantineUnreadableData()
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        #expect(try Data(contentsOf: persistence.quarantineURL) == Data("second".utf8))
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        let backups = names.filter { $0.hasPrefix("layout.json.corrupt.") }
        #expect(backups.count == 1)
        let backup = directory.appending(path: try #require(backups.first))
        #expect(try Data(contentsOf: backup) == Data("first".utf8))
    }
}
