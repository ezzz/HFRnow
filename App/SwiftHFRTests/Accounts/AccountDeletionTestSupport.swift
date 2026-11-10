import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Synchronization
import Testing

/// The per-account stores of the app, seeded with two accounts, so a test sees what an erase removes and what it keeps.
struct SeededStores {
    let drafts = DraftStore(persistence: InMemoryDraftPersistence())
    let pseudoLists = PseudoListStore(persistence: InMemoryPseudoListPersistence())
    let positions = ReadingPositionStore(persistence: InMemoryReadingPositionPersistence())
    let superFavorites = SuperFavoritesStore(persistence: InMemorySmallStorePersistence())
    let smileyFavorites = AppSmileyFavoritesStore(persistence: InMemorySmallStorePersistence())

    static let topic = TopicID(category: .forum(13), topic: 6510)
    static let smileyURL = URL(string: "https://forum-images.hardware.fr/images/perso/fake.gif")

    var eraser: AccountDataEraser {
        AccountDataEraser(
            drafts: drafts, pseudoLists: pseudoLists, positions: positions, superFavorites: superFavorites,
            smileyFavorites: smileyFavorites
        )
    }

    /// Writes one item of every kind for each account, and one allowlist entry (shared by every account).
    func seed(_ accounts: [String]) async throws {
        let url = try #require(Self.smileyURL)
        for account in accounts {
            try await drafts.save("brouillon de \(account)", for: .reply(topic: Self.topic, page: 1), account: account)
            _ = try await pseudoLists.block("member1", account: account)
            _ = try await positions.advance(Self.topic, to: ReadingPosition(page: 2, messageNumber: 201), account: account)
            _ = try await superFavorites.add(Self.topic, account: account)
            _ = try await smileyFavorites.add(code: "[:fake]", url: url, account: account)
        }
        _ = try await pseudoLists.allow("member2")
    }

    /// How many items of each kind `account` has, in `AccountDataKind.allCases` order.
    func counts(_ account: String) async -> [Int] {
        [
            await drafts.drafts(account: account).count,
            await pseudoLists.blocklist(for: account).count,
            await positions.records(for: account).count,
            await superFavorites.favorites(for: account).count,
            await smileyFavorites.favorites(for: account).count
        ]
    }
}

/// A draft file whose next saves can be made to fail (a full disk, a locked file).
final class FailingDraftPersistence: DraftPersistence {
    private let inner = InMemoryDraftPersistence()
    private let failures = Mutex(0)

    /// Makes the next `count` saves throw.
    func failNext(_ count: Int) {
        failures.withLock { $0 = count }
    }

    func load() throws -> DraftDocument? { try inner.load() }

    func save(_ document: DraftDocument) throws {
        let fails = failures.withLock { count in
            defer { count = max(0, count - 1) }
            return count > 0
        }
        if fails { throw CocoaError(.fileWriteOutOfSpace) }
        try inner.save(document)
    }

    func quarantineUnreadableData() throws { try inner.quarantineUnreadableData() }
}

/// A positions file that exists but cannot be read.
struct UnreadablePositionPersistence: ReadingPositionPersistence {
    func load() throws -> ReadingPositionDocument? { throw CocoaError(.fileReadCorruptFile) }
    func save(_ document: ReadingPositionDocument) throws {}
    func quarantineUnreadableData() throws {}
}

/// A credential store whose item cannot be deleted `failures` times (the Keychain refusing a delete).
final class UndeletableCredentialStore: CredentialStore {
    let inner: InMemoryCredentialStore
    private let failures: Mutex<Int>

    init(accounts: [Account], failures: Int) throws {
        inner = try InMemoryCredentialStore(accounts: accounts)
        self.failures = Mutex(failures)
    }

    func load() throws -> AccountBook { try inner.load() }

    func update<Value>(_ body: (inout AccountBook) throws -> Value) throws -> Value { try inner.update(body) }

    func removeAll() throws {
        let fails = failures.withLock { count in
            defer { count = max(0, count - 1) }
            return count > 0
        }
        if fails { throw CredentialStoreError.keychain(status: -25_308) }
        try inner.removeAll()
    }
}
