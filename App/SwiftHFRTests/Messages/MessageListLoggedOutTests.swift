import HFRModels
@testable import SwiftHFR
import Testing

// Legacy's logged-out Messages prompt (`MPListView.swift:588` @ 87fe0d1c, #1317).
@MainActor
struct MessageListLoggedOutTests {
    private func model(loggedIn: Bool) -> MessageListModel {
        MessageListModel(source: FakePrivateMessages(), isLoggedIn: { loggedIn })
    }

    private func row(_ status: AccountSessionStatus) -> AccountRow {
        AccountRow(id: "user1", displayName: "User1", isMain: true, avatar: nil, status: status)
    }

    @Test func withoutAccountMessagesShowsLegacyPrompt() async {
        let list = model(loggedIn: false)
        await list.onAppear()
        #expect(list.signInPrompt(current: nil) == SignInPrompt(
            title: "Connectez-vous pour accéder aux MP",
            message: "Ajoutez un pseudo pour charger vos messages privés.",
            systemImage: "envelope.badge",
            action: "Ajouter un pseudo",
            target: .newAccount
        ))
    }

    @Test func aCurrentAccountSignsInAgain() async {
        let list = model(loggedIn: false)
        await list.onAppear()
        let prompt = list.signInPrompt(current: row(.valid))
        #expect(prompt?.action == "Se reconnecter")
        #expect(prompt?.target == .existing(id: "user1", displayName: "User1"))
        #expect(prompt?.message == "Reconnectez-vous pour charger vos messages privés.")
    }

    @Test func anExpiredSessionSaysSo() async {
        let list = model(loggedIn: false)
        await list.onAppear()
        let message = list.signInPrompt(current: row(.expired))?.message
        #expect(message == "Votre session a expiré : reconnectez-vous pour charger vos messages privés.")
    }

    @Test func withAnAccountThereIsNoPrompt() async {
        let list = model(loggedIn: true)
        await list.onAppear()
        #expect(list.signInPrompt(current: nil) == nil)
    }

    @Test func noPromptBeforeTheFirstLoad() {
        #expect(model(loggedIn: false).signInPrompt(current: nil) == nil)
    }
}
