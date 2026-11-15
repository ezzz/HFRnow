import HFRStorage
import SwiftUI

// Port of HFRswift/Swift/AppSettingsView.swift (mpStorageSection) @ 87fe0d1c. Differences: the current account's state in
// words, the creation question asked here when switching on (GAP-181, ADR 0013 §7), "Dernier accès" persisted.
/// The "Stockage MP" section of Réglages (LOT-130). `model` is the current account's; nil when logged out.
struct MPStorageSettingsSection: View {
    let model: MPStorageSyncModel?

    var body: some View {
        Section("Stockage MP") {
            if let model {
                MPStorageSettingsRows(model: model)
            } else {
                Text("Connectez-vous pour utiliser le stockage MP.").foregroundStyle(.secondary)
            }
        }
    }
}

/// The rows of a logged-in account.
struct MPStorageSettingsRows: View {
    let model: MPStorageSyncModel

    var body: some View {
        Toggle(isOn: Binding(get: { model.isOn }, set: { enabled in Task { await model.setEnabled(enabled) } })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Activer le stockage MP")
                Text(Self.stateText(model.record?.state)).scaledFont(.footnote).foregroundStyle(.secondary)
            }
        }
        .disabled(model.status == .working)
        .task { await model.start() }
        .alert("Stockage MP", isPresented: Binding(get: { model.asksCreation }, set: { if !$0 { model.asksCreation = false } })) {
            Button("Créer") { Task { await model.answerCreation(true) } }
            Button("Annuler", role: .cancel) { Task { await model.answerCreation(false) } }
        } message: {
            Text(MPStorageSyncModel.creationQuestion)
        }
        if model.isOn {
            LabeledContent("Dernier accès", value: Self.lastSyncText(model.lastSync))
            Button("Resynchroniser") { Task { await model.resync() } }
                .disabled(model.status == .working)
        }
        if model.status == .working {
            ProgressView().frame(maxWidth: .infinity)
        } else if case .failed(let message) = model.status {
            Text(message).scaledFont(.footnote).foregroundStyle(.red)
        }
    }

    /// The account's state in words.
    static func stateText(_ state: MPStorageSyncState?) -> String {
        switch state {
        case .on?: "Activé pour ce compte"
        case .off?: "Désactivé pour ce compte"
        case .declined?: "Refusé pour ce compte"
        case .unasked?: "Pas encore choisi pour ce compte"
        case nil: "État enregistré illisible"
        }
    }

    /// "Dernier accès": the date of the last successful sync on this device, or "Jamais".
    static func lastSyncText(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "Jamais"
    }
}
