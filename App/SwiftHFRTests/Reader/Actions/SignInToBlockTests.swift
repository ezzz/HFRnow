import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// LOT-159 D3 (#1297), the reader's author menu: the handlers `TopicReaderView` registers (`PseudoListActionHandler.all`) show
/// « Connectez-vous pour bloquer » while logged out, in place of Blacklist, and open the login.
@MainActor
struct SignInToBlockTests {
    private func registry(account: String?, opened: Counter) -> MessageActionRegistry {
        let store = PseudoListStore(persistence: InMemoryPseudoListPersistence())
        let handlers = PseudoListActionHandler.all(
            manager: PseudoListManager(store: store, account: account), confirm: { _ in }, rebuild: {},
            login: { opened.count += 1 }
        )
        return MessageActionRegistry(handlers)
    }

    @MainActor final class Counter { var count = 0 }

    private func context() -> MessageMenuContext {
        MessageMenuContext(numreponse: 5, author: "autre", actions: MessageActions())
    }

    @Test func loggedOutTheAuthorMenuHasTheSignInEntryAndNoBlacklist() async {
        let opened = Counter()
        let registry = registry(account: nil, opened: opened)
        let entries = registry.entries(for: context(), source: .avatar)
        #expect(entries == [.signInToBlock, .allowlist])
        #expect(entries.first?.title == "Connectez-vous pour bloquer")
        #expect(await registry.perform(.signInToBlock, with: context()))
        #expect(opened.count == 1)
    }

    @Test func loggedInTheAuthorMenuIsUnchanged() async {
        let opened = Counter()
        let registry = registry(account: "moi", opened: opened)
        #expect(registry.entries(for: context(), source: .avatar) == [.blocklist, .allowlist])
        #expect(await !registry.perform(.signInToBlock, with: context()))
        #expect(opened.count == 0)
    }

    @Test func theSignInEntryBelongsToTheAuthorMenuOnly() {
        let registry = registry(account: nil, opened: Counter())
        #expect(!registry.entries(for: context(), source: .message).contains(.signInToBlock))
        #expect(registry.offers(.avatar))
    }
}
