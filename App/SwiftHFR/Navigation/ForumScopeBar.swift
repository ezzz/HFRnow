import SwiftUI

/// What a forum's topic list needs to offer its sub-forum picker and its filter: the category it belongs to, the shared filter
/// choice and how to open another source.
struct ForumScope {
    /// Read when the bar draws, so the menu appears once the home page has loaded, whatever view built the scope.
    let section: () -> ForumSection?
    let filter: TopicFilterModel
    /// Runs on the main actor: it writes the navigation model, and the picker binding hands it to SwiftUI as a `@Sendable` setter.
    let select: @MainActor (TopicSource) -> Void
}

// Port of HFRswift/Swift/MainWindow.swift (ForumTopicsListView.body: the "Sous-forum" picker and the filter, `:662-710`) @ 87fe0d1c.
// Differences: the filter is disabled on a sub-forum (GAP-022, 023); the notes are the app's own.
/// The first rows of a forum's topic list: the sub-forum menu (when the category has some), the filter and, when the filter is
/// off, why.
struct ForumScopeBar: View {
    let model: TopicListModel
    let scope: ForumScope

    var body: some View {
        Group {
            if let section = scope.section(), section.subforumCount > 0 { subforumRow(section) }
            Section {
                TopicFlagFilterPicker(filter: scope.filter, canFilter: model.offersFilter).densityRowMargin()
                if let note { Text(note).font(.footnote).foregroundStyle(.secondary).densityRowMargin() }
            }
        }
    }

    private func subforumRow(_ section: ForumSection) -> some View {
        LabeledContent("Sous-forum") {
            Picker("Sous-forum", selection: Binding(get: { model.source }, set: scope.select)) {
                Text("Tous les sous-forums").tag(section.source)
                ForEach(section.rows.dropFirst()) { Text($0.title).tag($0.source) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .densityRowMargin()
    }

    /// Why Favoris, Suivis and Lus cannot be chosen: legacy's note when logged out (`MainWindow.swift:699-706` @ 87fe0d1c), or
    /// the category-only rule on a sub-forum.
    private var note: String? {
        guard model.loader.value != nil, !model.offersFilter else { return nil }
        return model.isSignedIn
            ? "Le filtre s'applique à la catégorie entière : choisissez « Tous les sous-forums »."
            : "Connexion requise pour Favoris, Suivis et Lus. Vous pouvez consulter « Tous » sans compte."
    }
}
