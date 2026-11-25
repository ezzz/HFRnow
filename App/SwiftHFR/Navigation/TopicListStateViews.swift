import HFRModels
import SwiftUI

// The states and banners of `TopicListView`, in a file of their own to keep it under SwiftLint's length limits (#425).

/// Every section is folded and the options hide folded sections (legacy `allSectionsCollapsedState`).
struct AllSectionsCollapsedView: View {
    let options: FavoritesOptionsModel

    var body: some View {
        ContentUnavailableView {
            Label("Toutes les sections sont repliées", systemImage: "list.bullet.circle")
        } description: {
            Text("La vue filtrée masque les sections repliées.")
        } actions: {
            Button("Afficher les sections repliées") { options.showCollapsedSectionsFromEmptyState() }
            Button("Tout déplier") { Task { await options.expandAllFromEmptyState() } }
        }
    }
}

/// A sign-in prompt as an empty state: its button opens the login of its target, or the accounts when the store has a problem.
struct SignInPromptView: View {
    let prompt: SignInPrompt
    let refresh: () async -> Void
    @Environment(AccountsModel.self) private var accounts: AccountsModel?
    @State private var loginTarget: LoginTarget?
    @State private var showsAccounts = false

    var body: some View {
        EmptyStateView(
            title: prompt.title, symbol: prompt.systemImage, message: prompt.message,
            action: (prompt.action, { openLogin() }), refresh: refresh
        )
        .sheet(item: $loginTarget) { target in
            if let accounts { LoginView(target: target, accounts: accounts) }
        }
        .sheet(isPresented: $showsAccounts) { AccountsView() }
    }

    /// As the account button: a damaged account store is repaired in the accounts, not by adding another.
    private func openLogin() {
        if accounts?.storeProblem == nil { loginTarget = prompt.target } else { showsAccounts = true }
    }
}

struct EmptyListView: View {
    let reason: EmptyReason
    /// Favoris without an account: legacy's prompt, with its button instead of a refresh (#824); nil on every other list.
    var prompt: (AccountRow?) -> SignInPrompt? = { _ in nil }
    let refresh: () async -> Void
    @Environment(AccountsModel.self) private var accounts: AccountsModel?

    var body: some View {
        if let prompt = prompt(accounts?.current) {
            SignInPromptView(prompt: prompt, refresh: refresh)
        } else {
            EmptyStateView(title: title, symbol: "tray", message: message, refresh: refresh)
        }
    }

    private var title: String {
        switch reason {
        case .nothing: "Aucun sujet"
        case .signInRequired: "Connexion requise"
        case .notice: "Rien à afficher"
        }
    }

    private var message: String? {
        switch reason {
        case .nothing: nil
        case .signInRequired(let notice): notice ?? "Connectez-vous pour voir cette liste."
        case .notice(let notice): notice
        }
    }
}
