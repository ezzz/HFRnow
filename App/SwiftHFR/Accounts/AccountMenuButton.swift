import SwiftUI

// Port of HFRswift/Swift/MainToolbar.swift (MainToolbarContent, `:60-66`; ToolbarProfileImage) @ 87fe0d1c, of
// HFRswift/Swift/MainWindow.swift (CategoriesListView.accountMenuItems) and HFRswift/Swift/AccountMenuViews.swift (AccountMenuRow)
// @ 2440d79. Differences: a "manage accounts" entry (GAP-009, GAP-162); a pushed category topic list carries it after its back
// button (#425, `MainWindow.swift:803-818` @ 87fe0d1c); other pushed screens have none; an expired session shows the badge symbol
// instead of the avatar.
/// Toolbar entry to the accounts, as legacy's account menu (`HFRswift/Swift/MainWindow.swift:267-290`): switch account,
/// add one, manage them. Logged out, it offers to log in.
struct AccountMenuButton: View {
    /// Top left, as legacy (`MainToolbar.swift:60-66` @ 87fe0d1c) and on every main root (#1057).
    static let placement = ToolbarItemPlacement.topBarLeading

    /// The placement on `kind`'s display: top left, except on the iPhone Duo cover screen, where the bars are one column on the
    /// right edge (no left or right in it) and the button is drawn at the same spot either way. There it takes the trailing slot:
    /// iOS 27.2 lays a screen's `.bottomBar` items in an empty trailing slot, at the top of the column, and honours their flexible
    /// spacer only once that slot holds an item (measured on the Duo simulator, #1239; the cause of GAP-713's legacy defect).
    static func placement(on kind: PhoneDisplayKind) -> ToolbarItemPlacement {
        kind.placesThumbActionsAtBottom ? .topBarTrailing : placement
    }

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
                        .accessibilityAddTraits(row.isMain ? .isSelected : [])
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
                    menuLabel
                }
                .accessibilityLabel(accounts.current?.displayName ?? "Comptes")
                .accessibilityValue(accounts.current?.status == .expired ? "Session expirée" : "")
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

    /// The current account's avatar (legacy's `ToolbarProfileImage`), or the person symbol.
    @ViewBuilder
    private var menuLabel: some View {
        switch AccountMenuLabelContent.content(hasAvatar: accounts.current?.avatar != nil, status: accounts.current?.status) {
        case .avatar:
            AccountAvatarView(image: accounts.current?.avatar, scales: false)
        case .symbol(let name):
            Image(systemName: name)
        }
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

/// What the account menu's label shows.
enum AccountMenuLabelContent: Equatable {
    /// The current account's avatar.
    case avatar
    /// An SF Symbol.
    case symbol(String)

    /// The avatar when the account has one, the person symbol otherwise; an expired session always shows the badge.
    static func content(hasAvatar: Bool, status: AccountSessionStatus?) -> AccountMenuLabelContent {
        if status == .expired { return .symbol("person.crop.circle.badge.exclamationmark") }
        return hasAvatar ? .avatar : .symbol("person.crop.circle.fill")
    }
}

extension View {
    /// Puts the account button at the top left of this main root's bar (#1057; `AccountMenuButton.placement(on:)`).
    func accountMenuToolbarItem() -> some View {
        modifier(AccountMenuToolbarItem())
    }
}

private struct AccountMenuToolbarItem: ViewModifier {
    @Environment(\.phoneDisplayKind) private var phoneDisplayKind

    func body(content: Content) -> some View {
        content.toolbar { ToolbarItem(placement: AccountMenuButton.placement(on: phoneDisplayKind)) { AccountMenuButton() } }
    }
}
