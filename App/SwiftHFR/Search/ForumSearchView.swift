import HFRModels
import HFRNetwork
import SwiftUI

// Port of HFRswift/Swift/ForumSearchView.swift (ForumSearchView, ForumSearchViewModel) @ 2440d79.
// Differences: GAP-130..134. A banned word is refused with a warning instead of a silent substitution (Q-7,
// CHANGELOG-LEGACY 45); the result row is the app's `TopicRowView` with the excerpt; the pager follows LOT-046's paths.
// #1012 (GAP-978): a large title at landing, then the title pill, as the other main screens.
// LOT-185: the pager (legacy `:395-432`) is the system bottom bar (`PagerToolbar`) instead of a glass capsule; GAP row pending #545.
// #1107: the list look of every list (`listLook`): the Favoris card, or the dense look behind « Lignes denses ».

/// "Rechercher sur le forum" (Plus tab): the form, the results of the page on screen and a pager.
struct ForumSearchView: View {
    @Bindable var model: ForumSearchModel
    let forums: ForumListModel
    let reader: ReaderServices
    let composer: ComposerServices?
    @FocusState private var fieldFocused: Bool
    /// "Annuler" ended the load: no result to announce (the loader keeps the previous value).
    @State private var cancelledLoad = false
    @State private var titleVisibility = TitleVisibility()
    /// "Page numéro…" of a result's menu: the result asked about, and the page typed.
    @State private var pagePrompt: TopicSummary?
    @State private var pageText = ""

    var body: some View {
        List {
            // #1107: every row of the list takes its look, once for the whole content.
            Group {
                ScreenLargeTitle(title: "Recherche", visibility: titleVisibility)
                formSection
                resultsSection
            }
            .listLookRows()
        }
        .listLook()
        .screenTitle("Recherche", style: .largeThenPill, visibility: titleVisibility)
        .pagerBar(pager, hidden: fieldFocused)
        .navigationDestination(item: $model.selected) { topic in
            if let readerModel = model.reader(for: topic) {
                TopicReaderView(model: readerModel, services: reader, composer: composer).id(model.readerGeneration)
            } else {
                ContentUnavailableView("Sujet introuvable", systemImage: "questionmark.folder").appScreenBackground()
            }
        }
        .onChange(of: model.loader.isLoading) { wasLoading, isLoading in
            // The results land below the focused field: announce them (a search is a wait with no other cue).
            guard wasLoading, !isLoading else { return }
            guard !cancelledLoad else { cancelledLoad = false; return }
            if let error = model.loader.error {
                AccessibilityNotification.Announcement(error.title).post()
            } else if let content = model.loader.value {
                AccessibilityNotification.Announcement(summary(content)).post()
            }
        }
        .modifier(TopicPagePrompt(topic: $pagePrompt, text: $pageText, open: model.open))
        .onChange(of: forums.loader.value, initial: true) { _, content in model.setCategories(from: content) }
    }

    private var formSection: some View {
        Section {
            Group {
                TextField("Rechercher", text: $model.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($fieldFocused)
                    .onSubmit(submit)
                if let word = model.bannedWord {
                    StatusLabel(
                        text: "Le mot « \(word) » ne peut pas être recherché.", symbol: "exclamationmark.triangle.fill", tint: .orange
                    )
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
            }.themedListRow()
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        let loader = model.loader
        if let content = loader.value {
            ThemedSection(verbatim: summary(content)) {
                if content.topics.isEmpty {
                    Text(content.notice ?? "Aucun résultat").foregroundStyle(.secondary)
                }
                ForEach(content.topics) { topic in
                    SearchResultRow(topic: topic) { model.selected = topic }
                        .contextMenu {
                            TopicRowMenu(topic: topic, context: .globalSearch, open: model.open, askPage: { topic in
                                pageText = "\(TopicQuickActions.suggestedPage(of: topic))"
                                pagePrompt = topic
                            })
                        }
                }
            }
        }
        if loader.isLoading {
            Section {
                Group {
                    HStack { ProgressView(); Text("Recherche en cours").foregroundStyle(.secondary) }
                        .accessibilityElement(children: .combine)
                    Button("Annuler") { cancelledLoad = true; model.cancel() }
                }.themedListRow()
            }
        } else if let error = loader.error {
            Section {
                Group {
                    Label(error.title, systemImage: error.symbol)
                    Text(error.detail).font(.footnote).foregroundStyle(.secondary)
                    Button("Réessayer") { Task { await model.retry() } }
                }.themedListRow()
            }
        }
    }

    private var pager: PagerToolbar? {
        if let content = model.loader.value, content.previousPath != nil || content.nextPath != nil {
            return PagerToolbar(
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
        return nil
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
struct SearchResultRow: View {
    let topic: TopicSummary
    let open: () -> Void
    @Environment(\.listDensity) private var density

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 4) {
                TopicRowView(topic: topic)
                if let snippet = topic.searchHit?.snippet, !snippet.isEmpty {
                    Text(snippet).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            .themedRowText()
        }
        .buttonStyle(.plain)
        // On the row itself: the `listRowInsets` of the `TopicRowView` inside the stack is ignored by the list.
        .listRowInsets(density.rowInsets)
    }
}
