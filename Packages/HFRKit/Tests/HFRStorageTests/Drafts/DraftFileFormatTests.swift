import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// #1183: the v1 drafts file as the released builds write it, one draft per `DraftContext` case (both archived sources).
/// Case and label names of `DraftContext` (and `TopicID`, `CategoryID`, `ArchivedDraftSource`) are on-disk keys: a rename
/// that keeps every round trip green would make each member's drafts unreadable on upgrade. Captured from the writer at
/// dev-swift 1b6f98f0.
@Suite struct DraftFileFormatTests {
    static let versionOne = """
    {"drafts":[\
    {"account":"user1","context":{"reply":{"page":1,"topic":{"category":"13","topic":4242}}},\
    "text":"réponse","updatedAt":"2027-01-15T08:00:00Z"},\
    {"account":"user1","context":{"newTopic":{"forum":"13"}},"subject":"Sujet","text":"nouveau",\
    "updatedAt":"2027-01-15T08:00:00Z"},\
    {"account":"user1","context":{"privateMessage":{"recipient":"user2"}},"subject":"Objet","text":"mp",\
    "updatedAt":"2027-01-15T08:00:00Z"},\
    {"account":"user1","context":{"edit":{"post":77,"topic":{"category":"prive","topic":3207033}}},\
    "text":"édition","updatedAt":"2027-01-15T08:00:00Z"},\
    {"account":"user1","context":{"archivedReply":{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","source":"quote",\
    "topic":{"category":"13","topic":4242}}},"text":"de côté","updatedAt":"2027-01-15T08:00:00Z"},\
    {"account":"user1","context":{"archivedReply":{"id":"0E984725-C51C-4BF4-9960-E1C80E27ABA0","source":"quickReply",\
    "topic":{"category":"13","topic":4242}}},"text":"réponse rapide","updatedAt":"2027-01-15T08:00:00Z"},\
    {"account":"user1","context":{"legacyGlobal":{}},"text":"brouillon","updatedAt":"2027-01-15T08:00:00Z"}\
    ],"version":1}
    """

    static let date = Date(timeIntervalSince1970: 1_800_000_000)
    static let topic = TopicID(category: .forum(13), topic: 4242)

    /// The drafts `versionOne` holds, in its order.
    static func expected() throws -> [Draft] {
        let conversation = TopicID(category: .privateMessages, topic: 3_207_033)
        let id = try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        let quick = try #require(UUID(uuidString: "0E984725-C51C-4BF4-9960-E1C80E27ABA0"))
        return [
            Draft(context: .reply(topic: topic, page: 1), account: "user1", text: "réponse", updatedAt: date),
            Draft(context: .newTopic(forum: .forum(13)), account: "user1", text: "nouveau", subject: "Sujet", updatedAt: date),
            Draft(context: .privateMessage(recipient: "user2"), account: "user1", text: "mp", subject: "Objet", updatedAt: date),
            Draft(context: .edit(topic: conversation, post: 77), account: "user1", text: "édition", updatedAt: date),
            Draft(context: .archivedReply(topic: topic, id: id, source: .quote), account: "user1", text: "de côté", updatedAt: date),
            Draft(
                context: .archivedReply(topic: topic, id: quick, source: .quickReply), account: "user1", text: "réponse rapide",
                updatedAt: date
            ),
            Draft(context: .legacyGlobal, account: "user1", text: "brouillon", updatedAt: date)
        ]
    }

    private func file(holding text: String) throws -> (URL, FileDraftPersistence) {
        let directory = URL.temporaryDirectory.appending(path: "DraftFormat-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "drafts.json")
        try Data(text.utf8).write(to: url)
        return (directory, FileDraftPersistence(fileURL: url))
    }

    /// Passes by design today: its value is to fail on any later change of the format.
    @Test func readsTheVersion1FileOfEveryContext() throws {
        let (directory, persistence) = try file(holding: Self.versionOne)
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = try #require(try persistence.load())
        #expect(document.version == 1)
        #expect(document.drafts == (try Self.expected()))
    }

    /// The writer still writes that file (compared as parsed JSON: key order and spacing may differ between platforms).
    @Test func writesTheVersion1File() throws {
        let (directory, persistence) = try file(holding: "")
        defer { try? FileManager.default.removeItem(at: directory) }
        try persistence.save(DraftDocument(drafts: try Self.expected()))
        let written = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: "drafts.json")))
        let golden = try JSONSerialization.jsonObject(with: Data(Self.versionOne.utf8))
        #expect((written as? NSDictionary) == (golden as? NSDictionary))
    }

    /// One entry this build cannot read (a context of a newer build) is not the file: the others read, the file as it was is
    /// copied aside (`.corrupt`, byte for byte), and the readable drafts are written back, so the next load is clean.
    @Test func anUnreadableEntryIsSetAsideNotTheFile() async throws {
        let unknown = """
        {"account":"user1","context":{"poll":{"topic":{"category":"13","topic":1}}},"text":"futur",\
        "updatedAt":"2027-01-15T08:00:00Z"}
        """
        let text = Self.versionOne.replacingOccurrences(of: "\"drafts\":[", with: "\"drafts\":[\(unknown),")
        let (directory, persistence) = try file(holding: text)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DraftStore(persistence: persistence, clock: { Self.date })
        #expect(await store.draft(for: .reply(topic: Self.topic, page: 1), account: "user1")?.text == "réponse")
        #expect(await store.didRecoverFromCorruptData(), "the member is told once, as for a file set aside")
        #expect(try Data(contentsOf: persistence.quarantineURL) == Data(text.utf8))
        let rewritten = try #require(try persistence.load())
        #expect(rewritten.drafts == (try Self.expected()) && rewritten.unreadableEntryCount == 0)
        // The next load is clean: nothing more is set aside.
        let reopened = DraftStore(persistence: persistence, clock: { Self.date })
        #expect(await reopened.drafts(account: "user1").count == (try Self.expected()).count)
        #expect(await !reopened.didRecoverFromCorruptData())
    }

    /// An entry with a malformed date is one unreadable entry too.
    @Test func aBadDateIsOneUnreadableEntry() async throws {
        let bad = """
        {"account":"user1","context":{"legacyGlobal":{}},"text":"vieux","updatedAt":"hier"}
        """
        let text = Self.versionOne.replacingOccurrences(of: "\"drafts\":[", with: "\"drafts\":[\(bad),")
        let (directory, persistence) = try file(holding: text)
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = try #require(try persistence.load())
        #expect(document.drafts == (try Self.expected()) && document.unreadableEntryCount == 1)
        let store = DraftStore(persistence: persistence, clock: { Self.date })
        #expect(await store.accountKeys() == ["user1"])
        #expect(try Data(contentsOf: persistence.quarantineURL) == Data(text.utf8))
    }

    /// When the file cannot be copied aside, nothing is rewritten and writes stay blocked: no save may drop the entry.
    @Test func anEntryThatCannotBeSetAsideBlocksWrites() async throws {
        let unknown = #"{"account":"user1","context":{"poll":{}},"text":"futur","updatedAt":"2027-01-15T08:00:00Z"}"#
        let text = Self.versionOne.replacingOccurrences(of: "\"drafts\":[", with: "\"drafts\":[\(unknown),")
        let (directory, persistence) = try file(holding: text)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DraftStore(persistence: RefusingBackup(inner: persistence))
        #expect(await store.loadFailure() != nil)
        await #expect(throws: DraftError.self) { try await store.save("x", for: .legacyGlobal, account: "user1") }
        #expect(try Data(contentsOf: directory.appending(path: "drafts.json")) == Data(text.utf8))
    }

    /// A load whose write-back fails leaves one copy, however often it is retried (`reload()`), not one per attempt.
    @Test func aRetriedSetAsideKeepsOneCopy() async throws {
        let unknown = #"{"account":"user1","context":{"poll":{}},"text":"futur","updatedAt":"2027-01-15T08:00:00Z"}"#
        let text = Self.versionOne.replacingOccurrences(of: "\"drafts\":[", with: "\"drafts\":[\(unknown),")
        let (directory, persistence) = try file(holding: text)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DraftStore(persistence: RefusingSave(inner: persistence))
        #expect(await store.loadFailure() != nil)
        for _ in 0..<3 { _ = await store.reload() }
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        #expect(files.sorted() == ["drafts.json", "drafts.json.corrupt"])
    }

    /// A persistence that keeps a file but does not say how to copy it aside: the store blocks writes, never drops the entry.
    @Test func aPersistenceWithoutABackupBlocksWrites() async throws {
        let unknown = #"{"account":"user1","context":{"poll":{}},"text":"futur","updatedAt":"2027-01-15T08:00:00Z"}"#
        let text = Self.versionOne.replacingOccurrences(of: "\"drafts\":[", with: "\"drafts\":[\(unknown),")
        let (directory, persistence) = try file(holding: text)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DraftStore(persistence: Forwarding(inner: persistence))
        #expect(await store.loadFailure() != nil)
        #expect(try Data(contentsOf: directory.appending(path: "drafts.json")) == Data(text.utf8))
    }

    /// A file persistence whose saves fail.
    private struct RefusingSave: DraftPersistence {
        let inner: FileDraftPersistence
        func load() throws -> DraftDocument? { try inner.load() }
        func save(_ document: DraftDocument) throws { throw CocoaError(.fileWriteNoPermission) }
        func quarantineUnreadableData() throws { try inner.quarantineUnreadableData() }
        func backUpUnreadableData() throws { try inner.backUpUnreadableData() }
    }

    /// A wrapper that forwards everything but the backup.
    private struct Forwarding: DraftPersistence {
        let inner: FileDraftPersistence
        func load() throws -> DraftDocument? { try inner.load() }
        func save(_ document: DraftDocument) throws { try inner.save(document) }
        func quarantineUnreadableData() throws { try inner.quarantineUnreadableData() }
    }

    /// A persistence whose backup fails.
    private struct RefusingBackup: DraftPersistence {
        let inner: FileDraftPersistence
        func load() throws -> DraftDocument? { try inner.load() }
        func save(_ document: DraftDocument) throws { try inner.save(document) }
        func quarantineUnreadableData() throws { try inner.quarantineUnreadableData() }
        func backUpUnreadableData() throws { throw CocoaError(.fileWriteNoPermission) }
    }
}
