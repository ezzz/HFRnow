import SwiftUI
import UIKit

/// The accounts screen: select, add, log in again and remove accounts; shows a store problem with its way out.
struct AccountsView: View {
    @Environment(AccountsModel.self) private var accounts
    @Environment(\.dismiss) private var dismiss
    @State private var loginTarget: LoginTarget?
    @State private var pendingRemoval: AccountRow?
    @State private var confirmErase = false
    @State private var actionError: String?

    var body: some View {
        NavigationStack {
            List {
                if let problem = accounts.storeProblem {
                    storeProblemSection(problem)
                }
                if !accounts.rows.isEmpty {
                    Section("Comptes") {
                        ForEach(accounts.rows) { row in
                            AccountRowView(row: row, onSelect: { select(row) }, onRelogin: { relogin(row) })
                                .swipeActions {
                                    Button("Retirer", role: .destructive) { pendingRemoval = row }
                                }
                                .contextMenu {
                                    Button("Se reconnecter", systemImage: "arrow.clockwise") { relogin(row) }
                                    Button("Retirer", systemImage: "trash", role: .destructive) { pendingRemoval = row }
                                }
                        }
                    }
                }
                if accounts.storeProblem == nil {
                    Section {
                        Button("Ajouter un compte", systemImage: "person.badge.plus") { loginTarget = .newAccount }
                    } footer: {
                        Text("Vos mots de passe ne sont jamais enregistrés : seule la session du forum est gardée, dans le trousseau.")
                    }
                }
            }
            .navigationTitle("Comptes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .sheet(item: $loginTarget) { target in
                LoginView(target: target, accounts: accounts)
            }
            .confirmationDialog(
                "Retirer ce compte ?", isPresented: removalBinding, titleVisibility: .visible, presenting: pendingRemoval
            ) { row in
                Button("Retirer \(row.displayName)", role: .destructive) { remove(row) }
            } message: { _ in
                Text("Le compte est retiré de l’app. Vous pourrez l’ajouter de nouveau avec son mot de passe.")
            }
            .confirmationDialog("Effacer les comptes enregistrés ?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Effacer", role: .destructive) { Task { await accounts.eraseStoredAccounts() } }
            }
            .alert("Action impossible", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionError ?? "")
            }
        }
    }

    @ViewBuilder
    private func storeProblemSection(_ problem: StoreProblem) -> some View {
        Section {
            Label(AccountMessages.message(for: problem), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            switch problem {
            case .corrupted:
                Button("Effacer les comptes enregistrés", role: .destructive) { confirmErase = true }
            case .unavailable:
                Button("Réessayer") { Task { await accounts.retryRestore() } }
            case .newerVersion:
                EmptyView()
            }
        }
    }

    private var removalBinding: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    }

    private func select(_ row: AccountRow) {
        do {
            try accounts.select(row.id)
        } catch {
            actionError = AccountMessages.message(for: error)
        }
    }

    private func relogin(_ row: AccountRow) {
        loginTarget = .existing(id: row.id, displayName: row.displayName)
    }

    private func remove(_ row: AccountRow) {
        do {
            try accounts.remove(row.id)
        } catch {
            actionError = AccountMessages.message(for: error)
        }
    }
}

/// One account in the list: avatar, name, session state, and the action the state calls for.
struct AccountRowView: View {
    let row: AccountRow
    let onSelect: () -> Void
    let onRelogin: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    AccountAvatarView(data: row.avatarData)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.displayName)
                            .foregroundStyle(.primary)
                        if let status = AccountRowView.statusText(row.status) {
                            Text(status)
                                .font(.footnote)
                                .foregroundStyle(row.status == .expired ? .red : .secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if row.isMain {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Compte actuel")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if row.status == .expired {
                Button("Se reconnecter", action: onRelogin)
                    .buttonStyle(.bordered)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Short state line under the name; nil when there is nothing to say.
    static func statusText(_ status: AccountSessionStatus) -> String? {
        switch status {
        case .restored, .valid: nil
        case .checking: "Vérification de la session…"
        case .expired: "Session expirée"
        case .checkFailed: "Session non vérifiée (forum injoignable)"
        }
    }
}

/// An account's avatar, or a placeholder; scales with Dynamic Type.
struct AccountAvatarView: View {
    let data: Data?
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 32

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
