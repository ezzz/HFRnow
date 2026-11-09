import Foundation
import HFRClient
import HFRModels
@testable import SwiftHFR
import Testing

/// "Favoris" in the message menu (LOT-087) through LOT-125's flag actions: shown with a flag link, HFR's sentence or why not.
@MainActor
struct FavoriteActionHandlerTests {
    private let flagLink = url("https://forum.hardware.fr/user/addflag.php?config=hfr.inc&cat=13&post=28563&numreponse=42")

    private func context(favoriteURL: URL?) -> MessageMenuContext {
        MessageMenuContext(numreponse: 42, author: "auteur", actions: MessageActions(favoriteURL: favoriteURL), permalinkURL: nil)
    }

    private func handler(_ writer: FakeFlagWriter, told: @escaping @MainActor (String) -> Void) -> FavoriteActionHandler {
        FavoriteActionHandler(actions: TopicFlagActions(writer: writer), confirm: told)
    }

    @Test func favorisIsInTheMenuOnlyWithAFlagLink() {
        let registry = MessageActionRegistry([handler(FakeFlagWriter()) { _ in }])
        #expect(registry.entries(for: context(favoriteURL: flagLink), source: .message) == [.favorite])
        #expect(registry.entries(for: context(favoriteURL: nil), source: .message).isEmpty)
        #expect(registry.offers(.message) && !registry.offers(.avatar))
    }

    @Test func favorisFollowsTheMessagesFlagLinkAndShowsHFRsSentence() async {
        let writer = FakeFlagWriter()
        var told: [String] = []
        let registry = MessageActionRegistry([handler(writer) { told.append($0) }])
        await registry.perform(.favorite, with: context(favoriteURL: flagLink))
        #expect(writer.added == [flagLink])
        #expect(told == ["Favori positionné avec succès"])
    }

    @Test func aFailureSaysWhyAndIsNotResent() async {
        let writer = FakeFlagWriter()
        writer.addHandler = { (_) async throws(TopicFlagError) -> TopicFlagResult in throw .unconfirmed(.transport(.timedOut)) }
        var told: [String] = []
        await handler(writer) { told.append($0) }.perform(with: context(favoriteURL: flagLink))
        #expect(writer.added.count == 1)
        #expect(told == [TopicFlagActions.reason(for: .unconfirmed(.transport(.timedOut)))])
    }
}
