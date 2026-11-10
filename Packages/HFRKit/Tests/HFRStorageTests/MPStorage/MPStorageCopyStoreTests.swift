import Foundation
import Testing
@testable import HFRStorage

/// The device copies of the accounts' MPStorage documents (LOT-130).
@Suite struct MPStorageCopyStoreTests {
    static let copy = MPStorageCopy(
        post: 42, base: #"{"data":[]}"#, pending: nil, lastSync: Date(timeIntervalSince1970: 1_800_000_000)
    )

    @Test func copiesArePerAccountKey() async throws {
        let persistence = InMemorySmallStorePersistence<MPStorageCopyDocument>()
        let store = MPStorageCopyStore(persistence: persistence)
        #expect(await store.copy(for: "Alice") == MPStorageCopy())
        try await store.save(Self.copy, for: "Al\u{200B}ice")
        #expect(await store.copy(for: "ALICE") == Self.copy)
        #expect(await store.copy(for: "Bob") == MPStorageCopy())
        #expect(persistence.document?.accounts.keys.sorted() == ["alice"])
    }

    @Test func anEmptyAccountIsRefused() async {
        let store = MPStorageCopyStore(persistence: InMemorySmallStorePersistence<MPStorageCopyDocument>())
        await #expect(throws: SmallStoreError.emptyAccount) { try await store.save(Self.copy, for: "") }
    }

    @Test func aNewerFileIsNeverSavedOver() async {
        let newer = MPStorageCopyDocument(version: 2, accounts: ["alice": Self.copy])
        let persistence = InMemorySmallStorePersistence(newer)
        let store = MPStorageCopyStore(persistence: persistence)
        #expect(await store.copy(for: "Alice") == nil)
        #expect(await store.loadFailure() == .unsupportedVersion(2))
        await #expect(throws: SmallStoreError.unsupportedVersion(2)) { try await store.save(MPStorageCopy(), for: "Alice") }
        #expect(persistence.document == newer)
    }

    @Test func theFileRoundTrips() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "MPStorageCopyStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "copies.json")
        try await MPStorageCopyStore(persistence: FileSmallStorePersistence(fileURL: url)).save(Self.copy, for: "Alice")
        #expect(await MPStorageCopyStore(persistence: FileSmallStorePersistence(fileURL: url)).copy(for: "alice") == Self.copy)
    }
}
