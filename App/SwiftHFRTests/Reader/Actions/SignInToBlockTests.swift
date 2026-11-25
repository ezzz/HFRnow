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
            login: { opened.taps += 1 }
        )
        return MessageActionRegistry(handlers)
    }

    @MainActor final class Counter { var taps = 0 }

    private func context() -> MessageMenuContext {
        MessageMenuContext(numreponse: 5, author: "autre", actions: MessageActions())
    }

    @Test func loggedOutTheAuthorMenuHasTheSignInEntryAndNoBlocklist() async {
        let opened = Counter()
        let registry = registry(account: nil, opened: opened)
        let entries = registry.entries(for: context(), source: .avatar)
        #expect(entries == [.signInToBlock, .allowlist])
        #expect(entries.first?.title == "Connecte-toi pour bloquer")
        #expect(await registry.perform(.signInToBlock, with: context()))
        #expect(opened.taps == 1)
    }

    @Test func loggedInTheAuthorMenuIsUnchanged() async {
        let opened = Counter()
        let registry = registry(account: "moi", opened: opened)
        #expect(registry.entries(for: context(), source: .avatar) == [.blocklist, .allowlist])
        #expect(await !registry.perform(.signInToBlock, with: context()))
        #expect(opened.taps == 0)
    }

    // What the reader registers (`TopicReaderView` calls `pseudoListHandlers`): fails if it stops passing the sign-in handler or
    // does not reach the reader's login flag.
    @Test func theReaderRegistersTheSignInHandlerAndAsksItsViewForTheLogin() async {
        let store = PseudoListStore(persistence: InMemoryPseudoListPersistence())
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic)), source: FakeTopicPages())
        let loggedOut = MessageActionRegistry(reader.pseudoListHandlers(
            lists: PseudoListManager(store: store, account: nil), confirm: { _ in }, rebuild: {}
        ))
        #expect(loggedOut.entries(for: context(), source: .avatar) == [.signInToBlock, .allowlist])
        #expect(!reader.asksLogin)
        #expect(await loggedOut.perform(.signInToBlock, with: context()))
        #expect(reader.asksLogin)
        let loggedIn = MessageActionRegistry(reader.pseudoListHandlers(
            lists: PseudoListManager(store: store, account: "moi"), confirm: { _ in }, rebuild: {}
        ))
        #expect(loggedIn.entries(for: context(), source: .avatar) == [.blocklist, .allowlist])
        #expect(TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic)), source: FakeTopicPages())
            .pseudoListHandlers(lists: nil, confirm: { _ in }, rebuild: {}).isEmpty)
    }

    @Test func theSignInEntryBelongsToTheAuthorMenuOnly() {
        let registry = registry(account: nil, opened: Counter())
        #expect(!registry.entries(for: context(), source: .message).contains(.signInToBlock))
        #expect(registry.offers(.avatar))
    }
}
