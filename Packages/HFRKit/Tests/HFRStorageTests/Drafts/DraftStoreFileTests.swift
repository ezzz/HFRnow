import Foundation
import HFRModels
import Testing
@testable import HFRStorage

@Suite struct DraftStoreFileTests {
    private let topic = TopicID(category: .forum(13), topic: 4242)

    private func makeDirectory() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "Drafts-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func roundTripsThroughAFileWithoutTemporaryLeftovers() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "nested/drafts.json")
        let store = DraftStore(persistence: FileDraftPersistence(fileURL: file))
        try await store.save("Bonjour é 🙂", subject: "Sujet", for: .reply(topic: topic, page: 2), account: "Me")
        let reopened = DraftStore(persistence: FileDraftPersistence(fileURL: file))
        let draft = await reopened.draft(for: .reply(topic: topic, page: 2), account: "me")
        #expect(draft?.text == "Bonjour é 🙂")
        #expect(draft?.subject == "Sujet")
        #expect(try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path()) == ["drafts.json"])
    }

    @Test(arguments: ["", "not json", "{\"version\":1,\"drafts\":3}", "{}"])
    func undecodableFileIsSetAsideNotOverwritten(content: String) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "drafts.json")
        let persistence = FileDraftPersistence(fileURL: file)
        try Data(content.utf8).write(to: file)
        let store = DraftStore(persistence: persistence)
        #expect(await store.draft(for: .legacyGlobal, account: "me") == nil)
        #expect(await store.didRecoverFromCorruptData())
        try await store.save("fresh", for: .legacyGlobal, account: "me")
        #expect(try Data(contentsOf: persistence.quarantineURL) == Data(content.utf8))
        let reopened = DraftStore(persistence: persistence)
        #expect(await reopened.draft(for: .legacyGlobal, account: "me")?.text == "fresh")
    }

    @Test func newerVersionIsSetAsideToo() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "drafts.json")
        let persistence = FileDraftPersistence(fileURL: file)
        try persistence.save(DraftDocument(version: DraftDocument.currentVersion + 1))
        let original = try Data(contentsOf: file)
        let store = DraftStore(persistence: persistence)
        #expect(await store.didRecoverFromCorruptData())
        #expect(try Data(contentsOf: persistence.quarantineURL) == original)
    }

    @Test func healthyFileIsNotReportedAsRecovered() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DraftStore(persistence: FileDraftPersistence(fileURL: directory.appending(path: "drafts.json")))
        #expect(await !store.didRecoverFromCorruptData())
    }

    @Test func ioFailureWhileReadingBlocksWritesAndKeepsTheFile() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // A directory where the file should be: it exists but cannot be read as data.
        let file = directory.appending(path: "drafts.json", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        let store = DraftStore(persistence: FileDraftPersistence(fileURL: file))
        #expect(await store.loadFailure() != nil)
        await #expect(throws: DraftError.self) { try await store.save("x", for: .legacyGlobal, account: "me") }
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: file.path(), isDirectory: &isDirectory) && isDirectory.boolValue)
    }

    @Test func aSecondQuarantineKeepsTheFirstUnderAnotherName() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "drafts.json")
        let persistence = FileDraftPersistence(fileURL: file)
        try Data("one".utf8).write(to: file)
        try persistence.quarantineUnreadableData()
        try Data("two".utf8).write(to: file)
        try persistence.quarantineUnreadableData()
        #expect(try Data(contentsOf: persistence.quarantineURL) == Data("two".utf8))
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(Set(try contents.map { try Data(contentsOf: $0) }) == [Data("one".utf8), Data("two".utf8)])
    }
}
