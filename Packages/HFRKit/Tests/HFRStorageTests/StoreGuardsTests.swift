import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// #1184: the pseudo lists and the reading positions follow the small stores' load rules (`SmallStoreState`): the version
/// is read first, an empty account is refused, and an account has one key (`AccountKey`) whatever its spelling.
@Suite struct StoreGuardsTests {
    private static let cuisine = TopicID(category: .forum(13), topic: 28563)

    private func file(holding text: String, named name: String) throws -> (URL, URL) {
        let directory = URL.temporaryDirectory.appending(path: "StoreGuards-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try Data(text.utf8).write(to: url)
        return (directory, url)
    }

    // MARK: Formats (pinned before any change)

    /// The v1 pseudo-list file as the released builds write it: the legacy entry keys, blocklists by account key.
    @Test func readsTheVersion1PseudoListFile() async throws {
        let text = #"{"allowlist":[{"alias":"","mode":0,"word":"Ami"}],"#
            + #""blocklists":{"user1":[{"alias":"","mode":0,"word":"Spam"}]},"version":1}"#
        let (directory, url) = try file(holding: text, named: "lists.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PseudoListStore(persistence: FilePseudoListPersistence(fileURL: url))
        #expect(await store.blocklist(for: "user1").map(\.pseudo) == ["Spam"])
        #expect(await store.allowlist().map(\.pseudo) == ["Ami"])
    }

    // MARK: Version first

    /// A newer file whose shape changed is "update the app", not "file damaged".
    @Test func newerPseudoListVersionWithAnotherShapeIsReportedAsNewer() async throws {
        let (directory, url) = try file(holding: #"{"version":2,"lists":{}}"#, named: "lists.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PseudoListStore(persistence: FilePseudoListPersistence(fileURL: url))
        #expect(await store.loadFailure() == .unsupportedVersion(2))
    }

    @Test func newerPositionVersionWithAnotherShapeIsReportedAsNewer() async throws {
        let (directory, url) = try file(holding: #"{"version":2,"positions":[]}"#, named: "positions.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReadingPositionStore(persistence: FileReadingPositionPersistence(fileURL: url))
        #expect(await store.loadFailure() == .unsupportedVersion(2))
    }

    /// Every format starts at 1: a lower number is no file this code or an older one wrote.
    @Test func aVersionBelowOneIsUnreadable() async throws {
        let (directory, url) = try file(holding: #"{"version":0,"blocklists":{},"allowlist":[]}"#, named: "lists.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PseudoListStore(persistence: FilePseudoListPersistence(fileURL: url))
        guard case .loadFailed? = await store.loadFailure() else {
            Issue.record("expected loadFailed")
            return
        }
    }

    // MARK: Empty account

    @Test(arguments: ["", "\u{200B}"])
    func anEmptyAccountIsRefusedForABlocklist(_ account: String) async {
        let persistence = InMemoryPseudoListPersistence()
        let store = PseudoListStore(persistence: persistence)
        await #expect(throws: PseudoListError.emptyAccount) { try await store.block("Spam", account: account) }
        await #expect(throws: PseudoListError.emptyAccount) { try await store.replaceBlocklist(with: ["Spam"], account: account) }
        #expect(persistence.document == nil)
    }

    @Test func anAccountKeyEmptyOnceNormalizedIsRefusedForAPosition() async {
        let store = ReadingPositionStore(persistence: InMemoryReadingPositionPersistence())
        await #expect(throws: ReadingPositionError.emptyAccount) {
            try await store.advance(Self.cuisine, to: ReadingPosition(page: 2), account: "\u{200B}")
        }
    }

    // MARK: One key per account

    @Test func positionIsFoundWhateverTheAccountCase() async throws {
        let persistence = InMemoryReadingPositionPersistence()
        let store = ReadingPositionStore(persistence: persistence)
        try await store.advance(Self.cuisine, to: ReadingPosition(page: 3), account: "Alice")
        #expect(await store.position(of: Self.cuisine, account: "alice")?.page == 3)
        #expect(await store.position(of: Self.cuisine, account: "ALICE\u{200B}")?.page == 3)
        #expect(await store.accounts() == ["alice"])
        #expect(persistence.document?.accounts.keys.sorted() == ["alice"])
        #expect(try await store.removeAccount("ALICE"))
        #expect(await store.accounts().isEmpty)
    }

    /// Files written before stored positions under the spelling the reader used: they are merged on read, per topic the
    /// newest, and written under the key at the next save.
    @Test func spellingsStoredBeforeAreMergedOnRead() async throws {
        let older = ReadingPosition(page: 2, updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let newer = ReadingPosition(page: 5, updatedAt: Date(timeIntervalSince1970: 1_700_000_600))
        let other = TopicID(category: .privateMessages, topic: 42)
        let persistence = InMemoryReadingPositionPersistence(ReadingPositionDocument(accounts: [
            "Alice": [ReadingPositionRecord(topic: Self.cuisine, position: newer)],
            "alice": [
                ReadingPositionRecord(topic: Self.cuisine, position: older),
                ReadingPositionRecord(topic: other, position: older)
            ]
        ]))
        let store = ReadingPositionStore(persistence: persistence)
        #expect(await store.accounts() == ["alice"])
        #expect(await store.position(of: Self.cuisine, account: "Alice") == newer)
        #expect(await store.position(of: other, account: "alice") == older)
        try await store.advance(TopicID(category: .forum(1), topic: 1), to: ReadingPosition(page: 1), account: "alice")
        #expect(persistence.document?.accounts.keys.sorted() == ["alice"])
        #expect(persistence.document?.accounts["alice"]?.count == 3)
    }
}
