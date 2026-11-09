import HFRModels
import HFRNetwork
import SwiftUI

// Port of HFRswift/Swift/ForumSearchView.swift (ForumSearchView, ForumSearchViewModel) @ 2440d79.
// Differences: GAP-130..134. A banned word is refused with a warning instead of a silent substitution (Q-7,
// CHANGELOG-LEGACY 45); the result row is the app's `TopicRowView` with the excerpt; the pager follows LOT-046's paths.
// LOT-185: the pager (legacy `:395-432`) is the system bottom bar (`PagerToolbar`) instead of a glass capsule; GAP row pending #545.

/// "Rechercher sur le forum" (Plus tab): the form, the results of the page on screen and a pager.
struct ForumSearchView: View {
    @Bindable var model: ForumSearchModel
    let forums: ForumListModel
    let reader: ReaderServices
    let composer: ComposerServices?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        List {
            formSection
            resultsSection
        }
        .navigationTitle("Recherche")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { pagerToolbar }
        .navigationDestination(item: $model.selected) { topic in
            if let readerModel = model.reader(for: topic) {
                TopicReaderView(model: readerModel, services: reader, composer: composer)
            } else {
                ContentUnavailableView("Sujet introuvable", systemImage: "questionmark.folder")
            }
        }
        .onChange(of: forums.loader.value, initial: true) { _, content in model.setCategories(from: content) }
    }

    private var formSection: some View {
        Section {
            TextField("Rechercher", text: $model.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($fieldFocused)
                .onSubmit(submit)
            if let word = model.bannedWord {
                Label("Le mot « \(word) » ne peut pas être recherché.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }
            if model.hasShortWord {
                Text("Les mots de moins de 4 lettres peuvent être ignorés par la recherche du forum.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !model.categories.isEmpty {
                Picker("Catégorie", selection: $model.category) {
                    ForEach(model.categories) { Text($0.title).tag($0.id) }
                }
            }
            Picker("Mots", selection: $model.matchMode) {
                Text("Tous").tag(GlobalSearchQuery.MatchMode.allWords)
                Text("Au moins un").tag(GlobalSearchQuery.MatchMode.anyWord)
                Text("Avancé").tag(GlobalSearchQuery.MatchMode.advanced)
            }
            .pickerStyle(.segmented)
            Picker("Dans", selection: $model.scope) {
                Text("Titre et contenu").tag(GlobalSearchQuery.Scope.titleAndContent)
                Text("Titre").tag(GlobalSearchQuery.Scope.title)
                Text("Contenu").tag(GlobalSearchQuery.Scope.content)
            }
            Picker("Période", selection: $model.period) {
                ForEach(SearchPeriod.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Button(action: submit) { Label("Rechercher", systemImage: "magnifyingglass") }
                .disabled(!model.canSubmit)
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        let loader = model.loader
        if let content = loader.value {
            Section(summary(content)) {
                if content.topics.isEmpty {
                    Text(content.notice ?? "Aucun résultat").foregroundStyle(.secondary)
                }
                ForEach(content.topics) { topic in
                    Button { model.selected = topic } label: { SearchResultRow(topic: topic) }
                        .buttonStyle(.plain)
                }
            }
        }
        if loader.isLoading {
            Section {
                HStack { ProgressView(); Text("Recherche en cours").foregroundStyle(.secondary) }
                Button("Annuler") { model.cancel() }
            }
        } else if let error = loader.error {
            Section {
                Label(error.title, systemImage: error.symbol)
                Text(error.detail).font(.footnote).foregroundStyle(.secondary)
                Button("Réessayer") { Task { await model.retry() } }
            }
        }
    }

    @ToolbarContentBuilder
    private var pagerToolbar: some ToolbarContent {
        if let content = model.loader.value, content.previousPath != nil || content.nextPath != nil {
            PagerToolbar(
                first: .init(enabled: model.canGoToPrevious && content.firstPath != nil) {
                    Task { await model.goToFirstPage() }
                },
                previous: .init(enabled: model.canGoToPrevious) { Task { await model.goToPreviousPage() } },
                next: .init(enabled: model.canGoToNext) { Task { await model.goToNextPage() } },
                last: .init(enabled: model.canGoToNext && content.lastPath != nil) {
                    Task { await model.goToLastPage() }
                },
                status: .page(content.page)
            )
        }
    }

    private func summary(_ content: SearchContent) -> String {
        guard !content.topics.isEmpty else { return "Aucun résultat" }
        return "\(FrenchPlural.count(content.topics.count, "résultat", "résultats")) · p. \(content.page)"
    }

    private func submit() {
        guard model.canSubmit else { return }
        fieldFocused = false
        Task { await model.search() }
    }
}

/// A result: the topic row, then the excerpt of the matching message.
private struct SearchResultRow: View {
    let topic: TopicSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TopicRowView(topic: topic)
            if let snippet = topic.searchHit?.snippet, !snippet.isEmpty {
                Text(snippet).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
            }
        }
    }
}
