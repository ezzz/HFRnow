import HFRStorage
import SwiftUI

// Port of HFRswift/Swift/AppSettingsView.swift (mpStorageSection) @ 87fe0d1c. Differences: the current account's state in
// words, the creation question asked here when switching on (GAP-181, ADR 0013 §7), "Dernier accès" persisted, one switch
// per function with an info popover each (#859: legacy has the single `mpstorage_active` switch).
/// The "Stockage MP" section of Réglages (LOT-130). `model` is the current account's; nil when logged out.
struct MPStorageSettingsSection: View {
    let model: MPStorageSyncModel?

    var body: some View {
        Section {
            if let model {
                MPStorageSettingsRows(model: model)
            } else {
                Text("Connectez-vous pour utiliser le stockage MP.").foregroundStyle(.secondary)
            }
        } header: {
            Text("Stockage MP")
        } footer: {
            if model != nil { Text(MPStorageFunctionInfo.footer) }
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
            ForEach(MPStorageSyncModel.shippedFunctions, id: \.self) { function in
                MPStorageFunctionRow(function: function, model: model)
            }
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

/// The words of one function: its switch and the popover behind its ⓘ.
enum MPStorageFunctionInfo {
    /// Under the section: what MPStorage is, without any pseudo or MP id.
    static let footer = "Le stockage MP utilise un message privé comme espace de stockage, partagé avec les autres applications HFR+."

    static func title(_ function: MPStorageFunction) -> String {
        switch function {
        case .blacklist: "Liste noire partagée"
        case .bookmarks: "Favoris de messages"
        case .mpFlags: "MP multiples → dark topic"
        }
    }

    /// What it does, what it stores in the MP, what turning it off does.
    static func explanation(_ function: MPStorageFunction) -> String {
        switch function {
        case .blacklist:
            "Synchronise la liste noire avec vos autres appareils et applications. Elle est stockée dans le MP de stockage. "
                + "Désactivée, cette application ne lit ni n'écrit la liste noire dans le MP ; rien n'y est supprimé."
        case .bookmarks:
            "Synchronise vos favoris de messages avec vos autres appareils et applications. Ils sont stockés dans le MP de stockage. "
                + "Désactivée, cette application ne lit ni n'écrit les favoris dans le MP ; rien n'y est supprimé."
        case .mpFlags:
            "Affiche dans la liste des MP multiples la position de lecture (page) enregistrée par les autres applications HFR+ "
                + "dans le MP de stockage. Cette application ne l'écrit pas encore. "
                + "Désactivée, cette application ne lit pas ces positions ; rien n'y est supprimé, "
                + "ni les positions des autres applications."
        }
    }

    static func infoLabel(_ function: MPStorageFunction) -> String { "Plus d'infos sur \(title(function))" }
}

/// One function's switch with its ⓘ.
struct MPStorageFunctionRow: View {
    let function: MPStorageFunction
    let model: MPStorageSyncModel
    @State private var showsInfo = false

    var body: some View {
        HStack {
            Toggle(MPStorageFunctionInfo.title(function), isOn: Binding(
                get: { model.isEnabled(function) }, set: { model.setFunction(function, enabled: $0) }
            ))
            Button { showsInfo = true } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(MPStorageFunctionInfo.infoLabel(function))
            .popover(isPresented: $showsInfo) {
                Text(MPStorageFunctionInfo.explanation(function))
                    .padding()
                    .frame(minWidth: 260, maxWidth: 360)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }
}
