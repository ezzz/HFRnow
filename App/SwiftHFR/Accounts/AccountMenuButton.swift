import SwiftUI

/// Toolbar entry to the accounts, as legacy's account menu (`HFRswift/Swift/MainWindow.swift:267-290`): switch account,
/// add one, manage them. Logged out, it offers to log in.
struct AccountMenuButton: View {
    @Environment(AccountsModel.self) private var accounts
    @State private var showsAccounts = false
    @State private var loginTarget: LoginTarget?
    @State private var actionError: String?

    var body: some View {
        Group {
            if !accounts.hasRestored {
                // Until the store is read, neither "logged out" nor an account list would be true.
                Button("Comptes", systemImage: "person.crop.circle") {}
                    .disabled(true)
            } else if accounts.rows.isEmpty {
                Button("Se connecter", systemImage: "person.crop.circle") {
                    if accounts.storeProblem == nil { loginTarget = .newAccount } else { showsAccounts = true }
                }
            } else {
                Menu {
                    ForEach(accounts.rows) { row in
                        Button {
                            select(row)
                        } label: {
                            if row.isMain {
                                Label(row.displayName, systemImage: "checkmark")
                            } else {
                                Text(row.displayName)
                            }
                        }
                        .accessibilityValue(row.status == .expired ? "Session expirée" : "")
                    }
                    Divider()
                    if let current = accounts.current, current.status == .expired {
                        Button("Se reconnecter", systemImage: "arrow.clockwise") {
                            loginTarget = .existing(id: current.id, displayName: current.displayName)
                        }
                    }
                    Button("Ajouter un compte", systemImage: "person.badge.plus") { loginTarget = .newAccount }
                    Button("Gérer les comptes…", systemImage: "person.2") { showsAccounts = true }
                } label: {
                    Label(accounts.current?.displayName ?? "Comptes", systemImage: menuSymbol)
                }
            }
        }
        .sheet(isPresented: $showsAccounts) {
            AccountsView()
        }
        .sheet(item: $loginTarget) { target in
            LoginView(target: target, accounts: accounts)
        }
        .alert("Action impossible", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private var menuSymbol: String {
        accounts.current?.status == .expired ? "person.crop.circle.badge.exclamationmark" : "person.crop.circle.fill"
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
}
