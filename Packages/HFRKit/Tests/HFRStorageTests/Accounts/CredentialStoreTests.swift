import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// The kinds of store every behaviour test runs against.
enum StoreKind: String, CaseIterable, CustomTestStringConvertible {
    case memory, file

    var testDescription: String { rawValue }

    /// A fresh, empty store and the raw envelope accessors used to plant or inspect stored bytes.
    func make() throws -> StoreUnderTest {
        switch self {
        case .memory:
            let store = InMemoryCredentialStore()
            return StoreUnderTest(store: store, plant: { store.envelope = $0 }, raw: { store.envelope })
        case .file:
            let directory = URL.temporaryDirectory.appending(path: "hfr-credentials-\(UUID().uuidString)")
            let url = directory.appending(path: "accounts.json")
            let store = FileCredentialStore(fileURL: url)
            let plant: (Data) throws -> Void = { data in
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: url)
            }
            let raw: () throws -> Data? = {
                FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? try Data(contentsOf: url) : nil
            }
            return StoreUnderTest(store: store, plant: plant, raw: raw)
        }
    }
}

/// A store plus access to its raw bytes.
struct StoreUnderTest {
    let store: any CredentialStore
    let plant: (Data) throws -> Void
    let raw: () throws -> Data?
}

@Suite struct CredentialStoreTests {
    @Test(arguments: StoreKind.allCases)
    func anEmptyStoreHasNoAccountAndWritesNothing(kind: StoreKind) throws {
        let subject = try kind.make()
        let store = subject.store
        let raw = subject.raw
        #expect(try store.accounts().isEmpty)
        #expect(try store.mainAccount() == nil)
        #expect(try store.setMain(pseudo: "nobody") == false)
        #expect(try raw() == nil)
    }

    @Test(arguments: StoreKind.allCases)
    func accountsSurviveAReloadWithEveryField(kind: StoreKind) throws {
        let subject = try kind.make()
        let store = subject.store
        var account = makeAccount("alice", hash: "fake-hash")
        account.avatarData = Data([0xFF, 0xD8])
        account.displayName = "Alice"
        account.cookies[0].expiresDate = Date(timeIntervalSince1970: 1_900_000_000)
        try store.save(account)
        try store.save(makeAccount("bob"), makeMain: false)

        let reloaded = try store.load()
        #expect(reloaded.accounts.count == 2)
        #expect(reloaded.main == account.withMain(true))
    }

    @Test(arguments: StoreKind.allCases)
    func dedupePromotionAndMainSelectionGoThroughTheStore(kind: StoreKind) throws {
        let subject = try kind.make()
        let store = subject.store
        try store.save(makeAccount("alice"))
        try store.save(makeAccount("bob"))
        try store.save(makeAccount("ALICE", cookie: "fresh"), makeMain: false)
        #expect(try store.accounts().map(\.pseudo) == ["alice", "bob"])
        #expect(try store.mainAccount()?.pseudo == "bob")
        #expect(try store.setMain(pseudo: "alice"))
        #expect(try store.deleteAccount(pseudo: "alice")?.cookies.first?.value == "fresh")
        #expect(try store.mainAccount()?.pseudo == "bob")
    }

    @Test(arguments: StoreKind.allCases)
    func theEnvelopeIsVersionedAndHoldsNoPasswordField(kind: StoreKind) throws {
        let subject = try kind.make()
        let store = subject.store
        let raw = subject.raw
        try store.save(makeAccount("alice"))
        let data = try #require(try raw())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["version"] as? Int == CredentialEnvelope.currentVersion)
        let text = try #require(String(bytes: data, encoding: .utf8))
        #expect(!text.lowercased().contains("password"))
    }

    @Test(arguments: StoreKind.allCases)
    func aNewerEnvelopeIsNeitherReadNorOverwritten(kind: StoreKind) throws {
        let subject = try kind.make()
        let store = subject.store
        let plant = subject.plant
        let raw = subject.raw
        let newer = Data(#"{"version":2,"accounts":[],"vault":"opaque"}"#.utf8)
        try plant(newer)
        #expect(throws: CredentialStoreError.unsupportedVersion(2)) { try store.load() }
        #expect(throws: CredentialStoreError.unsupportedVersion(2)) { try store.save(makeAccount("alice")) }
        #expect(try raw() == newer)
    }

    @Test(arguments: StoreKind.allCases, [
        "not json",
        #"{"accounts":[]}"#,
        #"{"version":0,"accounts":[]}"#,
        #"{"version":"1","accounts":[]}"#,
        #"{"version":1,"accounts":{}}"#,
        #"{"version":1,"accounts":[{"pseudo":1}]}"#
    ])
    func aCorruptedEnvelopeIsNeverReplacedByAnEmptyOne(kind: StoreKind, content: String) throws {
        let subject = try kind.make()
        let store = subject.store
        let plant = subject.plant
        let raw = subject.raw
        try plant(Data(content.utf8))
        #expect(throws: CredentialStoreError.corrupted) { try store.load() }
        #expect(throws: CredentialStoreError.corrupted) { try store.deleteAccount(pseudo: "x") }
        #expect(try raw() == Data(content.utf8))
        // Only an explicit reset clears it.
        try store.removeAll()
        #expect(try store.accounts().isEmpty)
        try store.removeAll()
    }

    @Test(arguments: StoreKind.allCases)
    func aFailingEditWritesNothing(kind: StoreKind) throws {
        let subject = try kind.make()
        let store = subject.store
        let raw = subject.raw
        try store.save(makeAccount("alice"))
        let before = try raw()
        struct Abort: Error {}
        #expect(throws: Abort.self) {
            try store.update { book in
                book.remove(pseudo: "alice")
                throw Abort()
            }
        }
        #expect(try raw() == before)
    }

    @Test(arguments: StoreKind.allCases)
    func concurrentEditsAreSerialized(kind: StoreKind) async throws {
        let subject = try kind.make()
        let store = subject.store
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask { try store.save(makeAccount("user\(index)"), makeMain: false) }
            }
            try await group.waitForAll()
        }
        #expect(try store.accounts().count == 40)
        #expect(try store.load().accounts.filter(\.isMain).count == 1)
    }

    @Test func theFileIsOwnerOnly() throws {
        let directory = URL.temporaryDirectory.appending(path: "hfr-credentials-\(UUID().uuidString)")
        let url = directory.appending(path: "accounts.json")
        let store = FileCredentialStore(fileURL: url)
        try store.save(makeAccount("alice"))
        try store.save(makeAccount("bob"))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        #expect(leftovers == ["accounts.json"])
        try store.removeAll()
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func storeErrorsCarryNoSecret() throws {
        let store = InMemoryCredentialStore(envelope: Data(#"{"version":1,"accounts":[{"cookies":"SECRET-VALUE"}]}"#.utf8))
        let error = try #require(throws: CredentialStoreError.self) { try store.load() }
        #expect(!String(describing: error).contains("SECRET"))
        #expect(!String(reflecting: error).contains("SECRET"))
    }

    @Test func createdDirectoriesAreOwnerOnly() throws {
        let directory = URL.temporaryDirectory.appending(path: "hfr-credentials-\(UUID().uuidString)/nested")
        let store = FileCredentialStore(fileURL: directory.appending(path: "accounts.json"))
        try store.save(makeAccount("alice"))
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path(percentEncoded: false))
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    @Test func leftoverTemporaryCopiesAreSweptOnWriteAndRemoveAll() throws {
        let directory = URL.temporaryDirectory.appending(path: "hfr-credentials-\(UUID().uuidString)")
        let store = FileCredentialStore(fileURL: directory.appending(path: "accounts.json"))
        let manager = FileManager.default
        let plant = { (name: String) in
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("stale secret".utf8).write(to: directory.appending(path: name))
        }
        let names = { try manager.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted() }

        let crashed = ".accounts.json.\(UUID().uuidString).tmp"
        let folder = ".accounts.json.\(UUID().uuidString).tmp"
        try plant(crashed)
        try plant(".accounts.json.backup.tmp")
        try plant(".other.json.\(UUID().uuidString).tmp")
        try manager.createDirectory(at: directory.appending(path: folder), withIntermediateDirectories: true)
        try plant("\(folder)/keep")
        let kept = [folder, ".accounts.json.backup.tmp"] + (try names().filter { $0.hasPrefix(".other.json.") })
        try store.save(makeAccount("alice"))
        #expect(try names() == (kept + ["accounts.json"]).sorted())

        try plant(".accounts.json.\(UUID().uuidString).tmp")
        try store.removeAll()
        #expect(try names() == kept.sorted())
    }
}

extension Account {
    /// A copy with the main flag set, for comparisons.
    func withMain(_ isMain: Bool) -> Account {
        var copy = self
        copy.isMain = isMain
        return copy
    }
}
