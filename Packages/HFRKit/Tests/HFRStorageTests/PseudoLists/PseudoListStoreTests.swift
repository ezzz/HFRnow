import Foundation
import Testing
@testable import HFRStorage

@Suite struct PseudoListStoreTests {
    private func makeStore() -> (PseudoListStore, InMemoryPseudoListPersistence) {
        let persistence = InMemoryPseudoListPersistence()
        return (PseudoListStore(persistence: persistence), persistence)
    }

    @Test func blockIsIdempotentAndKeepsInsertionOrder() async throws {
        let (store, _) = makeStore()
        #expect(try await store.block("Zed", account: "me"))
        #expect(try await store.block("Alice", account: "me"))
        #expect(try await !store.block("alice", account: "me"))
        #expect(await store.blocklist(for: "me").map(\.pseudo) == ["Zed", "Alice"])
    }

    @Test func matchingIgnoresCaseAndZeroWidthSpace() async throws {
        let (store, _) = makeStore()
        try await store.block("Ma\u{200B}rc", account: "me")
        #expect(await store.isBlocked("MARC", account: "me"))
        #expect(await store.isBlocked("m\u{200B}arc", account: "me"))
        #expect(try await store.unblock("mArC", account: "me"))
        #expect(await !store.isBlocked("Marc", account: "me"))
    }

    @Test func unblockOfAnUnknownPseudoReportsFalseAndDoesNotSave() async throws {
        let (store, persistence) = makeStore()
        #expect(try await !store.unblock("ghost", account: "me"))
        #expect(persistence.document == nil)
    }

    @Test func blocklistsAreIsolatedPerAccountWhateverTheCaseOfTheAccountKey() async throws {
        let (store, _) = makeStore()
        try await store.block("Spammer", account: "Alice")
        #expect(await store.isBlocked("spammer", account: "alice"))
        #expect(await !store.isBlocked("spammer", account: "bob"))
        try await store.block("Other", account: "bob")
        #expect(await store.blocklist(for: "alice").map(\.pseudo) == ["Spammer"])
        #expect(await store.blocklist(for: "bob").map(\.pseudo) == ["Other"])
    }

    @Test func allowlistIsGlobalAndABlockedPseudoIsNeverAllowed() async throws {
        let (store, _) = makeStore()
        try await store.allow("Friend")
        #expect(await store.isAllowed("friend", account: "alice"))
        #expect(await store.isAllowed("FRIEND", account: "bob"))
        try await store.block("Friend", account: "bob")
        #expect(await !store.isAllowed("Friend", account: "bob"))
        #expect(await store.isAllowed("Friend", account: "alice"))
        #expect(try await store.disallow("friend"))
        #expect(try await !store.disallow("friend"))
        #expect(await store.allowlist().isEmpty)
    }

    @Test(arguments: ["", "\u{200B}", "\u{200B}\u{200B}"])
    func emptyPseudosAreRejectedOnBothLists(pseudo: String) async {
        let (store, persistence) = makeStore()
        await #expect(throws: PseudoListError.emptyPseudo) { try await store.block(pseudo, account: "me") }
        await #expect(throws: PseudoListError.emptyPseudo) { try await store.allow(pseudo) }
        #expect(persistence.document == nil)
    }

    @Test func replaceBlocklistCollapsesDuplicatesAndDropsEmptyPseudos() async throws {
        let (store, _) = makeStore()
        try await store.block("old", account: "me")
        #expect(try await store.replaceBlocklist(with: ["B", "b", "", "A", "\u{200B}"], account: "me"))
        #expect(await store.blocklist(for: "me").map(\.pseudo) == ["B", "A"])
        #expect(try await !store.replaceBlocklist(with: ["B", "A"], account: "me"))
        #expect(try await store.replaceBlocklist(with: [], account: "me"))
        #expect(await store.blocklist(for: "me").isEmpty)
    }

    @Test func changesSurviveANewStoreOverTheSamePersistence() async throws {
        let (store, persistence) = makeStore()
        try await store.block("Spammer", account: "me")
        try await store.allow("Friend")
        let reopened = PseudoListStore(persistence: persistence)
        #expect(await reopened.isBlocked("spammer", account: "me"))
        #expect(await reopened.isAllowed("friend", account: "me"))
    }

    @Test func concurrentWritesAreAllKept() async throws {
        let (store, persistence) = makeStore()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask { try await store.block("user\(index)", account: "me") }
            }
            try await group.waitForAll()
        }
        #expect(await store.blocklist(for: "me").count == 40)
        #expect(persistence.document?.blocklists["me"]?.count == 40)
    }
}
