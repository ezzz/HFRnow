import HFRModels
@testable import SwiftHFR
import Testing

// Legacy's logged-out prompts: Favoris (`Favorites.swift:667-680`) and the topic-list filter note (`MainWindow.swift:699-707`),
// both @ 87fe0d1c (#824).
@MainActor
struct TopicListLoggedOutTests {
    private func model(_ source: TopicSource, loggedIn: Bool, dataSource: FakeDataSource = FakeDataSource()) -> TopicListModel {
        TopicListModel(source: source, dataSource: dataSource, isLoggedIn: { loggedIn })
    }

    @Test(arguments: [TopicSource.favorites, TopicSource.flagged])
    func favorisWithoutAccountIsALoginWallEvenWhenHFRSaysNothing(source: TopicSource) async {
        let list = model(source, loggedIn: false)
        await list.loadIfNeeded()
        #expect(list.loader.value?.emptyReason == .signInRequired(nil))
    }

    @Test(arguments: [TopicSource.favorites, TopicSource.flagged])
    func favorisWithoutAccountShowsLegacyPrompt(source: TopicSource) async {
        let dataSource = FakeDataSource()
        dataSource.favoritesHandler = { _ in FavoritesPage(notice: "Aucun sujet que vous avez lu n'est connu") }
        let list = model(source, loggedIn: false, dataSource: dataSource)
        await list.loadIfNeeded()
        #expect(list.signInPrompt(current: nil) == SignInPrompt(
            title: "Connectez-vous pour accéder aux favoris",
            message: "Ajoutez un pseudo pour charger vos favoris et vos drapeaux.",
            systemImage: "star.slash",
            action: "Ajouter un pseudo",
            target: .newAccount
        ))
    }

    private func row(_ status: AccountSessionStatus) -> AccountRow {
        AccountRow(id: "user1", displayName: "User1", isMain: true, avatar: nil, status: status)
    }

    @Test func anExpiredCurrentAccountSignsInAgainLikeTheAccountButton() async {
        let list = model(.favorites, loggedIn: false)
        await list.loadIfNeeded()
        let prompt = list.signInPrompt(current: row(.expired))
        #expect(prompt?.action == "Se reconnecter")
        #expect(prompt?.target == .existing(id: "user1", displayName: "User1"))
        #expect(prompt?.message == "Votre session a expiré : reconnectez-vous pour charger vos favoris et vos drapeaux.")
    }

    @Test func aCurrentAccountThatIsNotExpiredStillGetsTheAddPrompt() async {
        let list = model(.favorites, loggedIn: false)
        await list.loadIfNeeded()
        #expect(list.signInPrompt(current: row(.valid))?.target == .newAccount)
    }

    @Test func favorisWithAnAccountHasNoPrompt() async {
        let list = model(.favorites, loggedIn: true)
        await list.loadIfNeeded()
        #expect(list.signInPrompt(current: nil) == nil)
        #expect(list.loader.value?.emptyReason == .nothing)
    }

    @Test func aForumListKeepsItsOwnWallWithoutTheFavorisPrompt() async {
        let list = model(.forum(.forum(13), title: "Discussions"), loggedIn: false)
        await list.loadIfNeeded()
        #expect(list.signInPrompt(current: nil) == nil)
    }

    @Test func theFilterNoteWithoutAccountHasLegacyTitleAndSubtitle() async {
        let list = model(.forum(.forum(13), title: "Discussions"), loggedIn: false)
        await list.loadIfNeeded()
        #expect(list.filterNote == FilterNote(
            title: "Connexion requise pour Favoris, Suivis et Lus",
            subtitle: "Vous pouvez consulter \"Tous\" sans compte.",
            systemImage: "person.crop.circle.badge.exclamationmark"
        ))
    }

    @Test func noFilterNoteBeforeTheFirstLoad() {
        #expect(model(.forum(.forum(13), title: "Discussions"), loggedIn: false).filterNote == nil)
    }
}
