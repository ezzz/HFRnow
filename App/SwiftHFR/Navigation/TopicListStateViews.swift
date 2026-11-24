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
    var prompt: SignInPrompt?
    let refresh: () async -> Void
    @Environment(AccountsModel.self) private var accounts: AccountsModel?
    @State private var loginTarget: LoginTarget?
    @State private var showsAccounts = false

    var body: some View {
        if let prompt {
            signInView(prompt)
        } else {
            emptyView
        }
    }

    private func signInView(_ prompt: SignInPrompt) -> some View {
        ContentUnavailableView {
            Label(prompt.title, systemImage: prompt.systemImage)
        } description: {
            Text(prompt.message)
        } actions: {
            Button(prompt.action) {
                // As the account button: a damaged account store is repaired in the accounts, not by adding another.
                if accounts?.storeProblem == nil { loginTarget = .newAccount } else { showsAccounts = true }
            }
            .buttonStyle(.borderedProminent)
        }
        .sheet(item: $loginTarget) { target in
            if let accounts { LoginView(target: target, accounts: accounts) }
        }
        .sheet(isPresented: $showsAccounts) { AccountsView() }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label(title, systemImage: "tray")
        } description: {
            if let message { Text(message) }
        } actions: {
            Button("Actualiser") { Task { await refresh() } }
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

/// HFR's confirmation of a new topic, above the list.
struct TopicSentBanner: View {
    let text: String
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
            Text(text).scaledFont(.subheadline)
            Spacer()
            Button(action: close) { Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                .accessibilityLabel("Masquer")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}
