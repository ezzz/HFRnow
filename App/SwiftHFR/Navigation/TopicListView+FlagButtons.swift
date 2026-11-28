import HFRModels
import SwiftUI

/// The flag buttons of a row, shared by its trailing swipe and its menu (#869); apart so the view stays under its length limit.
extension TopicListView {
    /// "Supprimer", « Retirer des favoris » on a favourite (legacy trailing swipe and menu entry, #869): "Suppression…" and
    /// disabled while the removal is in flight.
    func removeButton(_ topic: TopicSummary) -> some View {
        let removing = model.isRemovingFlag(topic)
        // Not the super favourite's `star.circle`: this one is an HFR write the list cannot undo (#869 review).
        let icon = model.isFavorite(topic) ? "star.slash" : "trash"
        return Button(role: .destructive) {
            Task { await model.removeFlag(topic) }
        } label: {
            Label(removing ? "Suppression…" : model.removeFlagTitle(topic), systemImage: removing ? "hourglass" : icon)
        }
        .disabled(removing)
    }

    /// « Ajouter aux favoris » (#869, option A): « Ajout… » and disabled while it is in flight.
    func addButton(_ topic: TopicSummary) -> some View {
        let adding = model.isAddingFavorite(topic)
        return Button {
            Task { await model.addFavorite(topic) }
        } label: {
            Label(adding ? "Ajout…" : "Ajouter aux favoris", systemImage: adding ? "hourglass" : "star")
        }
        .tint(.yellow)
        .disabled(adding)
    }

    /// « Ajouter aux / Retirer des super favoris » (#869; legacy had it in the Favoris row menu only, `Favorites.swift:1150-1158`
    /// @ 87fe0d1c).
    func superFavoriteButton(_ topic: TopicSummary) -> some View {
        Button {
            Task { await model.toggleSuperFavorite(topic) }
        } label: {
            Label(model.superFavoriteTitle(topic), systemImage: "star.circle")
        }
        .tint(.orange)
    }
}
