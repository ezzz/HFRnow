import SwiftUI

// Port of HFRswift/Swift/PlusTab.swift (AccountDeletionView) @ 87fe0d1c. Differences: GAP-166 (b, UXD-21 to settle): no mail
// composer and no address in source (Q-10); the screen opens HFR's own procedure page in the browser and erases one account's
// data from this device (LOT-157). The iPhone row opens this screen too (legacy opened the composer at once).
/// "Supprimer mon compte": the account belongs to HFR, which publishes its procedure; the app erases its own copy.
struct AccountDeletionView: View {
    @Environment(AccountsModel.self) private var accounts
    @Environment(AccountDeletionModel.self) private var deletion
    @State private var pendingErase: AccountRow?
    @State private var pendingLeftover: String?

    var body: some View {
        Form {
            Section {
                Text("Votre compte appartient au forum Hardware.fr, pas à cette app : l’app ne peut pas le supprimer à votre place.")
                Text(
                    "Hardware.fr explique sur sa page « Données personnelles » comment exercer vos droits, dont la suppression "
                        + "de vos données."
                )
                if let url = AccountDeletionModel.procedureURL {
                    Link(destination: url) {
                        Label("Ouvrir la page Données personnelles", systemImage: "safari")
                    }
                }
            } header: {
                Text("Votre compte HFR")
            }
            Section {
                if accounts.rows.isEmpty {
                    Text("Aucun compte n’est enregistré sur cet appareil.")
                        .foregroundStyle(.secondary)
                }
                ForEach(accounts.rows) { row in
                    Button("Effacer les données de \(row.displayName)", systemImage: "trash", role: .destructive) {
                        pendingErase = row
                    }
                    .disabled(deletion.isErasing)
                }
                // Data of accounts no longer in the app ("Retirer", a wipe that failed in part).
                ForEach(deletion.leftovers, id: \.self) { key in
                    Button("Effacer les données restantes de \(key)", systemImage: "trash", role: .destructive) {
                        pendingLeftover = key
                    }
                    .disabled(deletion.isErasing)
                }
                result
            } header: {
                Text("Cet appareil")
            } footer: {
                Text(
                    "La liste blanche, les sujets hors ligne, l’historique des images envoyées, les caches et les réglages sont "
                        + "communs à tous les comptes : ils restent sur l’appareil."
                )
            }
        }
        .navigationTitle("Supprimer mon compte")
        .navigationBarTitleDisplayMode(.inline)
        // Read again whenever the accounts change (a login, a removal elsewhere).
        .task(id: accounts.rows.map(\.id)) { await deletion.refreshLeftovers() }
        .confirmationDialog(
            "Effacer les données de ce compte ?", isPresented: eraseBinding, titleVisibility: .visible, presenting: pendingErase
        ) { row in
            // The dialog clears its item before the action runs: the action gets the row it was shown for (AGENTS.md §11, LOT-087).
            Button("Effacer \(row.displayName)", role: .destructive) {
                Task { await deletion.erase(row) }
            }
        } message: { _ in
            Text(Self.erasedItems)
        }
        .confirmationDialog(
            "Effacer les données restantes ?", isPresented: leftoverBinding, titleVisibility: .visible, presenting: pendingLeftover
        ) { key in
            Button("Effacer les données de \(key)", role: .destructive) {
                Task { await deletion.eraseLeftover(key) }
            }
        } message: { _ in
            Text(Self.leftoverItems)
        }
    }

    private static let erasedItems = "Le compte est retiré de l’app avec sa session, ses brouillons, sa liste noire, "
        + "ses positions de lecture, ses super-favoris et ses smileys favoris. Le compte HFR lui-même n’est pas supprimé."

    private static let leftoverItems = "Ce compte n’est plus dans l’app, mais des données sont restées sur l’appareil. "
        + "Le compte HFR lui-même n’est pas supprimé."

    @ViewBuilder
    private var result: some View {
        switch deletion.phase {
        case .idle:
            EmptyView()
        case .erasing(let name):
            HStack(spacing: 8) {
                ProgressView()
                Text("Effacement des données de \(name)…")
            }
        case .erased(let name):
            Label("Les données de \(name) ont été effacées de cet appareil.", systemImage: "checkmark.circle")
        case .partial(let name, let failures):
            Label(
                "Ces données de \(name) n’ont pas pu être effacées : \(failures.joined(separator: ", ")).",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.red)
            if deletion.keychainItemPending {
                Button("Réessayer") { Task { await deletion.retry() } }
                    .disabled(deletion.isErasing)
            }
        case .refused(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var eraseBinding: Binding<Bool> {
        Binding(get: { pendingErase != nil }, set: { if !$0 { pendingErase = nil } })
    }

    private var leftoverBinding: Binding<Bool> {
        Binding(get: { pendingLeftover != nil }, set: { if !$0 { pendingLeftover = nil } })
    }
}

#Preview {
    let accounts = AccountsModel.preview()
    NavigationStack { AccountDeletionView() }
        .environment(accounts)
        .environment(AccountDeletionModel(accounts: accounts, eraser: .inMemory()))
        .task { await accounts.restore() }
}
