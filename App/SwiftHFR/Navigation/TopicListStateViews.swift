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
    let refresh: () async -> Void

    var body: some View {
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
