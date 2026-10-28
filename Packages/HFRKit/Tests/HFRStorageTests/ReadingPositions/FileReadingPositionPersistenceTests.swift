import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// The JSON file: round trip, small records, and a corrupt file kept aside instead of overwritten.
@Suite struct FileReadingPositionPersistenceTests {
    static let cuisine = TopicID(category: .forum(13), topic: 28563)

    private func makeDirectory() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "ReadingPositions-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func missingFileLoadsAsNilWithoutCreatingAnything() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = FileReadingPositionPersistence(fileURL: directory.appending(path: "positions.json"))
        #expect(try persistence.load() == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path()).isEmpty)
    }

    @Test func storeRoundTripsThroughAFileAndLeavesNoTemporaryFile() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "nested/positions.json")
        let position = ReadingPosition(
            page: 3, messageNumber: 74_291_034, offset: 120, updatedAt: Date(timeIntervalSince1970: 1_700_000_000.5)
        )
        let store = ReadingPositionStore(persistence: FileReadingPositionPersistence(fileURL: file))
        try await store.advance(Self.cuisine, to: position, account: "user1")
        try await store.advance(TopicID(category: .privateMessages, topic: 42), to: ReadingPosition(page: 1), account: "user2")
        let reopened = ReadingPositionStore(persistence: FileReadingPositionPersistence(fileURL: file))
        #expect(await reopened.position(of: Self.cuisine, account: "user1") == position)
        #expect(await reopened.position(of: TopicID(category: .privateMessages, topic: 42), account: "user2")?.page == 1)
        let names = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path())
        #expect(names == ["positions.json"])
    }

    @Test func aRecordHoldsOnlyIdsAndNumbers() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "positions.json")
        let persistence = FileReadingPositionPersistence(fileURL: file)
        let position = ReadingPosition(page: 3, messageNumber: 900, updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let record = ReadingPositionRecord(topic: Self.cuisine, position: position)
        try persistence.save(ReadingPositionDocument(accounts: ["user1": [record]]))
        let text = String(bytes: try Data(contentsOf: file), encoding: .utf8) ?? ""
        #expect(
            text == #"{"accounts":{"user1":[{"position":{"messageNumber":900,"page":3,"updatedAt":1700000000},"#
                + #""topic":{"category":"13","topic":28563}}]},"version":1}"#
        )
    }

    @Test func aCorruptFileIsKeptAsideNeverOverwritten() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "positions.json")
        let garbage = Data("{not json".utf8)
        try garbage.write(to: file)
        let persistence = FileReadingPositionPersistence(fileURL: file)
        let store = ReadingPositionStore(persistence: persistence)
        await #expect(throws: ReadingPositionError.self) {
            try await store.advance(Self.cuisine, to: ReadingPosition(page: 2), account: "user1")
        }
        #expect(try Data(contentsOf: file) == garbage)
        try await store.discardUnreadableData()
        #expect(try Data(contentsOf: persistence.quarantineURL) == garbage)
        #expect(try await store.advance(Self.cuisine, to: ReadingPosition(page: 2), account: "user1"))
    }

    @Test func anEarlierQuarantineIsKeptUnderAUniqueName() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "positions.json")
        let persistence = FileReadingPositionPersistence(fileURL: file)
        try Data("first".utf8).write(to: persistence.quarantineURL)
        try Data("second".utf8).write(to: file)
        try persistence.quarantineUnreadableData()
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path())
        #expect(names.count == 2)
        #expect(try Data(contentsOf: persistence.quarantineURL) == Data("second".utf8))
    }
}
