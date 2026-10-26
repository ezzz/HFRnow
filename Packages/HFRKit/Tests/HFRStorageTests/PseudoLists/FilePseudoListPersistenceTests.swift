import Foundation
import Testing
@testable import HFRStorage

@Suite struct FilePseudoListPersistenceTests {
    private func makeDirectory() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "PseudoLists-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func missingFileLoadsAsNilWithoutCreatingAnything() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = FilePseudoListPersistence(fileURL: directory.appending(path: "lists.json"))
        #expect(try persistence.load() == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path()).isEmpty)
    }

    @Test func storeRoundTripsThroughAFileAndLeavesNoTemporaryFile() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "nested/lists.json")
        let store = PseudoListStore(persistence: FilePseudoListPersistence(fileURL: file))
        try await store.block("Spammer", account: "me")
        try await store.block("Other", account: "me")
        try await store.allow("Friend")
        let reopened = PseudoListStore(persistence: FilePseudoListPersistence(fileURL: file))
        #expect(await reopened.blocklist(for: "me").map(\.pseudo) == ["Spammer", "Other"])
        #expect(await reopened.isAllowed("friend", account: "me"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path()) == ["lists.json"])
    }

    @Test func fileUsesTheLegacyEntryKeys() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "lists.json")
        let store = PseudoListStore(persistence: FilePseudoListPersistence(fileURL: file))
        try await store.block("Spammer", account: "me")
        let text = String(bytes: try Data(contentsOf: file), encoding: .utf8) ?? ""
        #expect(text.contains("\"word\" : \"Spammer\""))
        #expect(text.contains("\"alias\" : \"\""))
        #expect(text.contains("\"mode\" : 0"))
    }

    @Test(arguments: ["", "not json", "{\"version\":1,\"blocklists\":3}", "{}"])
    func corruptFileBlocksWritesAndIsKeptByteForByte(content: String) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "lists.json")
        let original = Data(content.utf8)
        try original.write(to: file)
        let store = PseudoListStore(persistence: FilePseudoListPersistence(fileURL: file))
        await #expect(throws: PseudoListError.self) { try await store.block("New", account: "me") }
        #expect(try Data(contentsOf: file) == original)
    }

    @Test func discardMovesTheCorruptFileAsideInsteadOfDeletingIt() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "lists.json")
        let persistence = FilePseudoListPersistence(fileURL: file)
        try Data("broken".utf8).write(to: file)
        let store = PseudoListStore(persistence: persistence)
        try await store.discardUnreadableData()
        #expect(try Data(contentsOf: persistence.quarantineURL) == Data("broken".utf8))
        try await store.block("Fresh", account: "me")
        let reopened = PseudoListStore(persistence: persistence)
        #expect(await reopened.isBlocked("fresh", account: "me"))
    }

    @Test func aSecondQuarantineKeepsTheFirstUnderAnotherName() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "lists.json")
        let persistence = FilePseudoListPersistence(fileURL: file)
        try Data("one".utf8).write(to: file)
        try persistence.quarantineUnreadableData()
        try Data("two".utf8).write(to: file)
        try persistence.quarantineUnreadableData()
        #expect(try Data(contentsOf: persistence.quarantineURL) == Data("two".utf8))
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let saved = try contents.map { try Data(contentsOf: $0) }
        #expect(Set(saved) == [Data("one".utf8), Data("two".utf8)])
    }
}
