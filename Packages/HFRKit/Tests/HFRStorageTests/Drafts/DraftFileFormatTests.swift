import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// #1183: the v1 drafts file as the released builds write it, one draft per `DraftContext` case. Case and label names of
/// `DraftContext` (and `TopicID`, `CategoryID`, `ArchivedDraftSource`) are on-disk keys: a rename that keeps every round trip
/// green would make each member's drafts unreadable on upgrade. Captured from the writer at dev-swift 1b6f98f0.
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
    {"account":"user1","context":{"legacyGlobal":{}},"text":"brouillon","updatedAt":"2027-01-15T08:00:00Z"}\
    ],"version":1}
    """

    static let date = Date(timeIntervalSince1970: 1_800_000_000)
    static let topic = TopicID(category: .forum(13), topic: 4242)

    /// The drafts `versionOne` holds, in its order.
    static func expected() throws -> [Draft] {
        let conversation = TopicID(category: .privateMessages, topic: 3_207_033)
        let id = try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        return [
            Draft(context: .reply(topic: topic, page: 1), account: "user1", text: "réponse", updatedAt: date),
            Draft(context: .newTopic(forum: .forum(13)), account: "user1", text: "nouveau", subject: "Sujet", updatedAt: date),
            Draft(context: .privateMessage(recipient: "user2"), account: "user1", text: "mp", subject: "Objet", updatedAt: date),
            Draft(context: .edit(topic: conversation, post: 77), account: "user1", text: "édition", updatedAt: date),
            Draft(context: .archivedReply(topic: topic, id: id, source: .quote), account: "user1", text: "de côté", updatedAt: date),
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

    /// One entry this build cannot read (a context of a newer build) is not the file: the others read, nothing is set aside,
    /// and the entry is written back as it was on the next save, so the newer build still finds it.
    @Test func anUnknownContextDropsOneDraftNotTheFile() async throws {
        let unknown = """
        {"account":"user1","context":{"poll":{"topic":{"category":"13","topic":1}}},"text":"futur",\
        "updatedAt":"2027-01-15T08:00:00Z"}
        """
        let text = Self.versionOne.replacingOccurrences(of: "\"drafts\":[", with: "\"drafts\":[\(unknown),")
        let (directory, persistence) = try file(holding: text)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DraftStore(persistence: persistence, clock: { Self.date })
        #expect(await store.draft(for: .reply(topic: Self.topic, page: 1), account: "user1")?.text == "réponse")
        #expect(await !store.didRecoverFromCorruptData())
        #expect(!FileManager.default.fileExists(atPath: persistence.quarantineURL.path(percentEncoded: false)))
        try await store.save("modifié", for: .legacyGlobal, account: "user1")
        let saved = try #require(try persistence.load())
        #expect(saved.drafts.count == 6)
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: "drafts.json"))) as? [String: Any]
        let entries = try #require(raw?["drafts"] as? [[String: Any]])
        #expect(entries.contains { ($0["text"] as? String) == "futur" })
    }

    /// An entry with a malformed date is one unreadable entry too.
    @Test func aBadDateIsOneUnreadableEntry() throws {
        let bad = """
        {"account":"user1","context":{"legacyGlobal":{}},"text":"vieux","updatedAt":"hier"}
        """
        let text = Self.versionOne.replacingOccurrences(of: "\"drafts\":[", with: "\"drafts\":[\(bad),")
        let (directory, persistence) = try file(holding: text)
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = try #require(try persistence.load())
        #expect(document.drafts == (try Self.expected()))
    }
}
