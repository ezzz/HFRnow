import SwiftUI

/// The way out of a local store the app cannot read (#1182): every screen that shows such a failure offers the same action,
/// asks first, and only then sets the data aside. The engine keeps the unreadable bytes as a `.corrupt` copy, never deletes
/// them, and the store starts empty and writable again.
enum UnreadableDataRecovery {
    /// The button under the failure.
    static let buttonTitle = "Repartir de zéro…"
    /// The confirmation's title and its destructive choice.
    static let confirmationTitle = "Repartir de zéro ?"
    static let confirmTitle = "Repartir de zéro"
    /// What the confirmation says happens: `content` names the data in the plural ("les listes de pseudos", "les images
    /// envoyées").
    static func message(for content: String) -> String {
        "L'app ne sait plus lire \(content) de cet appareil. Le fichier est gardé de côté, il n'est pas effacé, "
            + "et \(content) repartent de zéro sur cet appareil."
    }

    /// What the screen shows when the set-aside failed.
    static let failure = "Impossible de mettre les données illisibles de côté. Réessaie plus tard."
}

/// The "Repartir de zéro…" button and its confirmation; `discard` runs only after the member confirmed.
struct UnreadableDataRecoveryButton: View {
    /// The data, in a French phrase that takes a plural verb ("les listes de pseudos").
    let content: String
    let discard: () async -> Void
    @State private var isAsking = false

    var body: some View {
        Button(UnreadableDataRecovery.buttonTitle, role: .destructive) { isAsking = true }
            .confirmationDialog(UnreadableDataRecovery.confirmationTitle, isPresented: $isAsking, titleVisibility: .visible) {
                Button(UnreadableDataRecovery.confirmTitle, role: .destructive) { Task { await discard() } }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text(UnreadableDataRecovery.message(for: content))
            }
    }
}
