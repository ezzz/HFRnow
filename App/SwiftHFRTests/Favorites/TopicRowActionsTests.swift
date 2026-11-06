import Foundation
import HFRClient
import HFRModels
@testable import SwiftHFR
import Testing

/// The row actions of the lists (LOT-125): "Lu" stays local until the next load, "Supprimer" acts only on HFR's confirmation.
@MainActor
struct TopicRowActionsTests {
    private func favoritesList(
        _ topics: [TopicSummary], writer: FakeFlagWriter? = FakeFlagWriter(), source: TopicSource = .flagged
    ) async -> (TopicListModel, FakeDataSource) {
        let data = FakeDataSource()
        data.favoritesHandler = { _ in FavoritesPage(sections: [favoriteSection(13, topics)]) }
        let model = TopicListModel(
            source: source, dataSource: data, isLoggedIn: { true },
            flagActions: writer.map { TopicFlagActions(writer: $0) }
        )
        await model.loadIfNeeded()
        return (model, data)
    }

    private func forumList(_ topics: [TopicSummary], writer: FakeFlagWriter) async -> TopicListModel {
        let data = FakeDataSource()
        data.topicHandler = { _, _ in TopicListPage(topics: topics, navigation: PageNavigation(current: 1, last: 1)) }
        let model = TopicListModel(
            source: .forum(.forum(13), title: "Discussions"), dataSource: data, isLoggedIn: { true },
            flagActions: TopicFlagActions(writer: writer)
        )
        await model.loadIfNeeded()
        return model
    }

    private func titles(_ model: TopicListModel) -> [String] { model.displayedGroups.flatMap(\.topics).map(\.title) }

    @Test func luShowsTheRowReadSendsNothingAndLastsUntilTheNextLoad() async {
        let writer = FakeFlagWriter()
        let topic = flaggedTopic(1)
        let (model, _) = await favoritesList([topic], writer: writer)
        #expect(!model.isRead(topic))
        model.markRead(topic)
        #expect(model.isRead(topic))
        #expect(writer.removed.isEmpty && writer.added.isEmpty)
        await model.refresh()
        #expect(!model.isRead(topic))
    }

    @Test func aFailedLoadKeepsTheLocalMarks() async {
        let topic = flaggedTopic(1)
        let (model, data) = await favoritesList([topic])
        model.markRead(topic)
        data.favoritesHandler = { (_) async throws(ListLoadError) -> FavoritesPage in throw .offline }
        await model.refresh()
        #expect(model.isRead(topic))
    }

    @Test func aForumRowWithoutFlagOffersNeitherSwipe() async {
        let plain = flaggedTopic(1, flag: nil)
        let flagged = flaggedTopic(2)
        let model = await forumList([plain, flagged], writer: FakeFlagWriter())
        #expect(!model.canMarkRead(plain) && !model.canRemoveFlag(plain))
        model.markRead(plain)
        #expect(!model.isRead(plain))
        #expect(model.canMarkRead(flagged) && model.canRemoveFlag(flagged))
    }

    @Test func supprimerIsHiddenLoggedOutAndWithoutATopicNumber() async {
        let topic = flaggedTopic(1)
        let (loggedOut, _) = await favoritesList([topic], writer: nil)
        #expect(!loggedOut.canRemoveFlag(topic))
        #expect(loggedOut.canMarkRead(topic))
        var anonymous = flaggedTopic(2)
        anonymous.topicID = nil
        let (model, _) = await favoritesList([anonymous])
        #expect(!model.canRemoveFlag(anonymous))
    }

    @Test func aConfirmedRemovalTakesTheRowOutOfTheFavouritesList() async {
        let writer = FakeFlagWriter()
        let kept = flaggedTopic(1)
        let removed = flaggedTopic(2)
        let (model, _) = await favoritesList([kept, removed], writer: writer)
        await model.removeFlag(removed)
        #expect(writer.removed == [TopicID(category: .forum(13), topic: 2)])
        #expect(titles(model) == ["Sujet 1"])
        #expect(model.actionFailure == nil)
        #expect(!model.isRemovingFlag(removed))
    }

    @Test func aConfirmedRemovalKeepsAForumRowWithoutItsFlag() async {
        let topic = flaggedTopic(3)
        let model = await forumList([topic], writer: FakeFlagWriter())
        await model.removeFlag(topic)
        #expect(titles(model) == ["Sujet 3"])
        #expect(!model.hasFlag(topic))
        #expect(!model.canRemoveFlag(topic) && !model.canMarkRead(topic))
    }

    @Test(arguments: [
        TopicFlagError.unconfirmed(.unrecognizedAnswer(message: nil)),
        TopicFlagError.network(.offline),
        TopicFlagError.rejected(message: "Refusé"),
        TopicFlagError.sessionNotConfirmed(.expired(.noIdentityCookie)),
        TopicFlagError.missingToken,
        TopicFlagError.notLoggedIn
    ])
    func aFailureRestoresTheRowAndSaysWhyInFrench(error: TopicFlagError) async {
        let writer = FakeFlagWriter()
        writer.removeHandler = { (_) async throws(TopicFlagError) -> TopicFlagResult in throw error }
        let topic = flaggedTopic(1)
        let (model, _) = await favoritesList([topic], writer: writer)
        await model.removeFlag(topic)
        #expect(titles(model) == ["Sujet 1"])
        #expect(model.hasFlag(topic))
        #expect(model.actionFailure == TopicFlagActions.reason(for: error))
        #expect(writer.removed.count == 1)
        model.clearActionFailure()
        #expect(model.actionFailure == nil)
    }

    @Test func anUnconfirmedRemovalIsNeverResentOnItsOwn() async {
        let writer = FakeFlagWriter()
        writer.removeHandler = { (_) async throws(TopicFlagError) -> TopicFlagResult in
            throw .unconfirmed(.transport(.timedOut))
        }
        let topic = flaggedTopic(1)
        let (model, _) = await favoritesList([topic], writer: writer)
        await model.removeFlag(topic)
        #expect(writer.removed.count == 1)
        #expect(model.actionFailure?.contains("Actualisez pour vérifier") == true)
    }

    @Test func aRemovalInFlightIsNotSentTwice() async {
        let writer = FakeFlagWriter()
        let gate = AsyncGate()
        writer.removeHandler = { topic in
            await gate.wait()
            return confirmed(.removeFavoriteFromList, topic, "Drapeaux effacés avec succès")
        }
        let topic = flaggedTopic(1)
        let (model, _) = await favoritesList([topic], writer: writer)
        let first = Task { await model.removeFlag(topic) }
        while !model.isRemovingFlag(topic) { await Task.yield() }
        await model.removeFlag(topic)
        #expect(writer.removed.count == 1)
        await gate.open()
        await first.value
        #expect(!model.isRemovingFlag(topic))
        #expect(titles(model).isEmpty)
    }

    @Test func theNextLoadShowsHFRsStateAgain() async {
        let topic = flaggedTopic(1)
        let (model, _) = await favoritesList([topic])
        await model.removeFlag(topic)
        #expect(titles(model).isEmpty)
        await model.refresh()
        #expect(titles(model) == ["Sujet 1"])
    }

    @Test func everyFailureSaysWhetherAnythingLeft() {
        let notSent: [TopicFlagError] = [
            .invalidLink, .invalidTopic, .sessionNotConfirmed(.expired(.noIdentityCookie)), .missingToken, .network(.offline)
        ]
        for error in notSent { #expect(TopicFlagActions.reason(for: error).contains("rien n'a été envoyé")) }
        #expect(TopicFlagActions.reason(for: .unconfirmed(.transport(.timedOut))).contains("a pu être faite"))
        #expect(TopicFlagActions.reason(for: .rejected(message: "Non")) == "HFR a refusé : Non")
        #expect(TopicFlagActions.reason(for: .rejected(message: nil)) == "HFR a refusé l'action.")
    }
}

/// Holds a scripted answer until the test opens it.
actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
