import Foundation
import HFRClient
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// #869, option A: « Ajouter aux favoris » on a row that is no favourite, one addition per swipe, the row a favourite only on
/// HFR's confirmation, and the four transitions (add, remove; super favourite add, remove) in a row.
@MainActor
struct TopicFavoriteAddTests {
    private func list(
        _ source: TopicSource, _ topics: [TopicSummary], writer: FakeFlagWriter? = FakeFlagWriter()
    ) async -> (TopicListModel, FakeDataSource) {
        let data = FakeDataSource()
        data.topicHandler = { _, _ in TopicListPage(topics: topics, navigation: PageNavigation(current: 1, last: 1)) }
        data.favoritesHandler = { _ in FavoritesPage(sections: [favoriteSection(13, topics)]) }
        let model = TopicListModel(
            source: source, dataSource: data, isLoggedIn: { true }, superFavorites: favoritesOptions(),
            flagActions: writer.map { TopicFlagActions(writer: $0) }
        )
        await model.onAppear()
        return (model, data)
    }

    private static let category = TopicSource.forum(.forum(13), title: "Discussions")

    /// A « Tous » row without flag and a followed row of Drapeaux: the add reads the row's last page, once.
    @Test(arguments: [(TopicSource.forum(.forum(13), title: "Discussions"), nil), (.flagged, .blue)] as [(TopicSource, TopicFlag?)])
    func ajouterAuxFavorisSendsOneAdditionWithTheRowsLastPage(source: TopicSource, flag: TopicFlag?) async throws {
        let writer = FakeFlagWriter()
        let row = flaggedTopic(1, pages: 5, flag: flag)
        let id = try #require(row.topicID)
        let (model, _) = await list(source, [row], writer: writer)
        #expect(model.canAddFavorite(row) && !model.isFavorite(row))
        await model.addFavorite(row)
        #expect(writer.addedFromList == [ListAddition(topic: id, page: 5)])
        #expect(writer.removed.isEmpty && writer.added.isEmpty)
        #expect(model.isFavorite(row) && !model.canAddFavorite(row))
        #expect(model.canRemoveFlag(row) && model.removeFlagTitle(row) == "Retirer des favoris")
        #expect(model.actionFailure == nil)
    }

    @Test func aFavouriteRowIsNeverOfferedTheAdd() async {
        let favourite = flaggedTopic(1, flag: .yellow)
        let (forum, _) = await list(Self.category, [favourite])
        #expect(!forum.canAddFavorite(favourite))
        let (favoris, _) = await list(.favorites, [flaggedTopic(2, flag: nil)])
        #expect(!favoris.canAddFavorite(flaggedTopic(2, flag: nil)))
    }

    @Test func noAddLoggedOutNorOnAPrivateConversation() async {
        let row = flaggedTopic(1, flag: nil)
        let (loggedOut, _) = await list(Self.category, [row], writer: nil)
        #expect(!loggedOut.canAddFavorite(row))
        var conversation = flaggedTopic(2, flag: nil)
        conversation.topicID = TopicID(category: .privateMessages, topic: 2)
        let (model, _) = await list(Self.category, [conversation])
        #expect(!model.canAddFavorite(conversation))
    }

    /// The four transitions on one category row: add, remove, then the super favourite on and off; each label follows.
    @Test func theFourTransitionsFollowTheRowsState() async {
        let writer = FakeFlagWriter()
        let row = flaggedTopic(1, flag: nil)
        let (model, _) = await list(Self.category, [row], writer: writer)
        await model.addFavorite(row)
        #expect(model.isFavorite(row) && model.removeFlagTitle(row) == "Retirer des favoris")
        await model.removeFlag(row)
        #expect(!model.isFavorite(row) && model.canAddFavorite(row) && !model.canRemoveFlag(row))
        #expect(writer.addedFromList.count == 1 && writer.removed.count == 1)
        await model.toggleSuperFavorite(row)
        #expect(model.superFavoriteTitle(row) == "Retirer des super favoris")
        await model.toggleSuperFavorite(row)
        #expect(model.superFavoriteTitle(row) == "Ajouter aux super favoris")
    }

    @Test(arguments: [
        TopicFlagError.favoriteLinkMissing, .unconfirmed(.unrecognizedAnswer(message: nil)),
        .sessionNotConfirmed(.expired(.noIdentityCookie))
    ])
    func aFailedAdditionKeepsTheRowSaysWhyAndIsNeverResent(error: TopicFlagError) async {
        let writer = FakeFlagWriter()
        writer.listAddHandler = { (_: TopicID, _: Int) async throws(TopicFlagError) -> TopicFlagResult in throw error }
        let row = flaggedTopic(1, flag: nil)
        let (model, _) = await list(Self.category, [row], writer: writer)
        await model.addFavorite(row)
        #expect(!model.isFavorite(row) && model.canAddFavorite(row))
        #expect(model.actionFailure == TopicFlagActions.reason(for: error))
        #expect(model.actionFailureTitle == AlertTitles.favoriteAddFailed)
        #expect(model.retryableAddition == nil && model.retryableRemoval == nil)
        #expect(writer.addedFromList.count == 1)
    }

    /// Nothing left and the cause may pass: the alert offers « Réessayer », which sends the addition again, never a removal.
    @Test func aRetryableFailureOffersTheAdditionsRetry() async {
        let writer = FakeFlagWriter()
        writer.listAddHandler = { (_: TopicID, _: Int) async throws(TopicFlagError) -> TopicFlagResult in throw .sessionChanged }
        let row = flaggedTopic(1, flag: .blue)
        let (model, _) = await list(Self.category, [row], writer: writer)
        await model.addFavorite(row)
        #expect(model.retryableAddition == row && model.retryableRemoval == nil)
        #expect(model.actionFailureTitle == AlertTitles.favoriteAddFailed)
        model.clearActionFailure()
        #expect(model.retryableAddition == nil)
        #expect(writer.removed.isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func anAdditionInFlightIsNotSentTwice() async {
        let writer = FakeFlagWriter()
        let gate = AsyncGate()
        writer.listAddHandler = { topic, _ in
            await gate.wait()
            return confirmed(.addFavorite, topic, "Favori positionné avec succès")
        }
        let row = flaggedTopic(1, flag: nil)
        let (model, _) = await list(Self.category, [row], writer: writer)
        let first = Task { await model.addFavorite(row) }
        // Waits for the request at the writer, so the second swipe meets an addition really in flight (as the removal's test).
        while writer.addedFromList.isEmpty { await Task.yield() }
        #expect(model.isAddingFavorite(row))
        await model.addFavorite(row)
        await gate.open()
        await first.value
        #expect(writer.addedFromList.count == 1)
        #expect(!model.isAddingFavorite(row) && model.isFavorite(row))
    }

    /// Drapeaux: an addition confirmed after a removal of the same row wins, so the row stays listed, a favourite (#869 review).
    @Test(.timeLimit(.minutes(1))) func anAdditionConfirmedAfterARemovalKeepsTheRowListed() async {
        let writer = FakeFlagWriter()
        let removal = AsyncGate()
        let addition = AsyncGate()
        writer.removeHandler = { topic in
            await removal.wait()
            return confirmed(.removeFavoriteFromList, topic, "Drapeaux effacés avec succès")
        }
        writer.listAddHandler = { topic, _ in
            await addition.wait()
            return confirmed(.addFavorite, topic, "Favori positionné avec succès")
        }
        let row = flaggedTopic(1, flag: .blue)
        let (model, _) = await list(.flagged, [row], writer: writer)
        let remove = Task { await model.removeFlag(row) }
        let add = Task { await model.addFavorite(row) }
        while writer.removed.isEmpty || writer.addedFromList.isEmpty { await Task.yield() }
        await removal.open()
        await remove.value
        #expect(model.displayedGroups.flatMap(\.topics).isEmpty)
        await addition.open()
        await add.value
        #expect(model.displayedGroups.flatMap(\.topics) == [row])
        #expect(model.isFavorite(row) && model.removeFlagTitle(row) == "Retirer des favoris")
    }

    /// The confirmed addition lasts until a load that starts after it; that load shows HFR's own state again.
    @Test func theNextLoadShowsHFRsStateAgain() async {
        let row = flaggedTopic(1, flag: nil)
        let (model, _) = await list(Self.category, [row])
        await model.addFavorite(row)
        #expect(model.isFavorite(row))
        await model.refresh()
        #expect(!model.isFavorite(row) && model.canAddFavorite(row))
    }
}
