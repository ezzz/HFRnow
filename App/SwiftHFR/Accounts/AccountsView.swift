import SwiftUI
import UIKit

// Port of HFRswift/Swift/AccountMenuViews.swift (AccountMenuRow, AccountAvatarView) and the "Déconnexion" item of
// HFRswift/Swift/Favorites.swift (FavoritesListView) @ 2440d79. Differences: a manage screen where an account is removed after
// confirmation (GAP-163). #1107: the list look of every list (`listLook`).
/// The accounts screen: select, add, log in again and remove accounts; shows a store problem with its way out.
struct AccountsView: View {
    @Environment(AccountsModel.self) private var accounts
    @Environment(\.dismiss) private var dismiss
    @State private var loginTarget: LoginTarget?
    @State private var pendingRemoval: AccountRow?
    @State private var confirmErase = false
    @State private var actionError: String?

    var body: some View {
        ThemedNavigationStack {
            List {
                // #1107: every row of the list takes its look, once for the whole content.
                Group {
                    if let problem = accounts.storeProblem {
                        storeProblemSection(problem)
                    }
                    if !accounts.rows.isEmpty {
                        ThemedSection("Comptes") {
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
                            Text(Self.footer).themedSectionHeader()
                        }
                    }
                }
                .listLookRows()
            }
            .listLook()
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
                Text("Le compte est retiré de l’app. Tu pourras l’ajouter de nouveau avec son mot de passe.")
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
            StatusLabel(text: AccountMessages.message(for: problem), symbol: "exclamationmark.triangle.fill", tint: .red)
            switch problem {
            case .corrupted:
                Button("Effacer les comptes enregistrés", role: .destructive) { confirmErase = true }
            case .unavailable:
                Button("Réessayer") { Task { await accounts.retryRestore() } }
                    .disabled(accounts.isRestoring)
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

    /// Below "Ajouter un compte": what is kept, and why a session expires (LOT-156). HFR sets the login cookies for 30 days at
    /// the login and again on the logged-in home page and followed list the app loads (HFR-PROTOCOL §6b, `W03`, `R74`; other
    /// pages not captured).
    static let footer = """
        Tes mots de passe ne sont jamais enregistrés : seule la session du forum est gardée, dans le trousseau. \
        HFR garde un compte connecté 30 jours, prolongés chaque fois que l’app ouvre le forum avec ce compte ; passé ce délai, \
        « Se reconnecter » suffit, et les brouillons, listes et réglages du compte restent.
        """

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
                    AccountAvatarView(image: row.avatar)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.displayName)
                            .foregroundStyle(.primary)
                        if let status = AccountRowView.statusText(row.status, expiry: row.sessionExpiry) {
                            Text(status)
                                .scaledFont(.footnote)
                                .foregroundStyle(row.status == .expired ? AccessibleColors.errorText : Color.secondary)
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

    /// Short state line under the name; nil when there is nothing to say. A session the forum confirmed shows when its login
    /// cookies lapse without a visit (LOT-156): only then is the date the one the forum set. A date already past says nothing
    /// true (a re-login whose store write failed leaves the old cookies stored): no line then.
    static func statusText(_ status: AccountSessionStatus, expiry: Date? = nil, now: Date = Date()) -> String? {
        switch status {
        case .restored: nil
        case .valid: expiry.flatMap { $0 > now ? "Session valable jusqu’au \($0.formatted(expiryStyle))" : nil }
        case .checking: "Vérification de la session…"
        case .expired: "Session expirée : reconnecte-toi"
        case .checkFailed: "Session non vérifiée (forum injoignable)"
        }
    }

    /// "18 décembre", in the device's time zone (the date the user lives in).
    static let expiryStyle = Date.FormatStyle(locale: Locale(identifier: "fr_FR")).day().month(.wide)
}

/// An account's avatar (decoded by `AccountsModel`), or a placeholder; scales with Dynamic Type.
struct AccountAvatarView: View {
    let image: UIImage?
    /// False in a bar, where legacy's avatar is a fixed 32 pt (`MainToolbar.swift:70-77` @ 87fe0d1c) and a larger one would outgrow it.
    var scales = true
    @ScaledMetric(relativeTo: .body) private var scaledSize: CGFloat = 32
    private var size: CGFloat { scales ? scaledSize : 32 }

    var body: some View {
        Group {
            if let image {
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
