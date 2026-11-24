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
            Button("Afficher les sections repliées") { options.showsCollapsedSections = true }
            Button("Tout déplier") { Task { await options.expandAll() } }
        }
    }
}

struct EmptyListView: View {
    let reason: EmptyReason
    /// Favoris without an account: legacy's prompt, with its button instead of a refresh (#824); nil on every other list.
    var prompt: (AccountRow?) -> SignInPrompt? = { _ in nil }
    let refresh: () async -> Void
    @Environment(AccountsModel.self) private var accounts: AccountsModel?
    @State private var loginTarget: LoginTarget?
    @State private var showsAccounts = false

    var body: some View {
        if let prompt = prompt(accounts?.current) {
            EmptyStateView(
                title: prompt.title, symbol: prompt.systemImage, message: prompt.message,
                action: (prompt.action, { openLogin(prompt) }), refresh: refresh
            )
            .sheet(item: $loginTarget) { target in
                if let accounts { LoginView(target: target, accounts: accounts) }
            }
            .sheet(isPresented: $showsAccounts) { AccountsView() }
        } else {
            EmptyStateView(title: title, symbol: "tray", message: message, refresh: refresh)
        }
    }

    /// As the account button: a damaged account store is repaired in the accounts, not by adding another.
    private func openLogin(_ prompt: SignInPrompt) {
        if accounts?.storeProblem == nil { loginTarget = prompt.target } else { showsAccounts = true }
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
