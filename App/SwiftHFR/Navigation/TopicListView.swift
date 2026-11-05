import HFRModels
import SwiftUI

// Port of HFRswift/Swift/MainWindow.swift (ForumTopicsListView, ForumTopicsPaginationBar) and HFRswift/Swift/Favorites.swift
// (FavoritesListView) @ 2440d79. Differences: no Tous / Favoris / Suivis / Lus filter; "Page N" without a fake total (GAP-023, 024;
// UXD).
/// The middle column: the topics of the selected source, with pagination for forums.
struct TopicListView: View {
    let model: TopicListModel
    @Binding var selection: TopicSummary?
    /// The post filter, offered on a favourite's context menu (LOT-114); nil hides the entry.
    var filtering: FilteredPostsModel?
    /// The current account's composer (LOT-089); nil when logged out, which hides "Nouveau sujet".
    var composer: ComposerServices?
    @State private var newTopic: ReplyComposerModel?

    var body: some View {
        let loader = model.loader
        List(selection: $selection) {
            if let content = loader.value {
                ForEach(content.groups) { group in
                    if let title = group.title {
                        Section(title) { rows(group.topics) }
                    } else {
                        rows(group.topics)
                    }
                }
            }
        }
        .navigationTitle(model.source.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay { overlay(loader) }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 8) {
                if let confirmation = model.sentConfirmation {
                    TopicSentBanner(text: confirmation, close: model.clearSentConfirmation)
                }
                if let error = loader.error, loader.value != nil {
                    LoadFailureBanner(error: error, retry: model.retry)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.source.isPaged, loader.value != nil { PageBar(model: model) }
        }
        .toolbar {
            if let composer, let target = model.newTopicTarget {
                ToolbarItem(placement: .primaryAction) {
                    Button { newTopic = ReplyComposerModel(composing: .newTopic(target), services: composer) } label: {
                        Label("Nouveau sujet", systemImage: "square.and.pencil")
                    }
                }
            }
        }
        .sheet(item: $newTopic) { composer in
            ReplyComposerView(model: composer) { reason in
                Task { await model.newTopicDidClose(reason) }
            }
        }
        .task(id: model.sentConfirmation) {
            guard model.sentConfirmation != nil else { return }
            // Long enough to read, like the reply banner (LOT-084); cancelled when another confirmation replaces it.
            guard (try? await Task.sleep(for: .seconds(4))) != nil else { return }
            model.clearSentConfirmation()
        }
        .refreshable { await model.refresh() }
        .task { await model.onAppear() }
    }

    private func rows(_ topics: [TopicSummary]) -> some View {
        ForEach(topics) { topic in
            TopicRowView(topic: topic).tag(topic)
                .contextMenu {
                    if model.source == .favorites, let filtering, topic.topicID != nil {
                        Button { filtering.start(opening: topic) } label: {
                            Label("Filtrer les posts", systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .disabled(filtering.isBusy)
                    }
                }
        }
    }

    @ViewBuilder
    private func overlay(_ loader: ContentLoader<TopicListContent>) -> some View {
        if let content = loader.value {
            if content.isEmpty, let reason = content.emptyReason { EmptyListView(reason: reason, refresh: model.refresh) }
        } else if let error = loader.error {
            LoadFailureView(error: error, retry: model.retry)
        } else if loader.isLoading {
            ProgressView("Chargement des sujets")
        }
    }
}

private struct EmptyListView: View {
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

/// Previous / next controls. Only "a next page exists" is known: the pager is a window, never a total.
private struct PageBar: View {
    let model: TopicListModel

    var body: some View {
        HStack {
            Button { Task { await model.goToFirstPage() } } label: { Image(systemName: "backward.end") }
                .disabled(!model.canGoToPrevious)
                .accessibilityLabel("Première page")
            Button { Task { await model.goToPreviousPage() } } label: { Image(systemName: "chevron.left") }
                .disabled(!model.canGoToPrevious)
                .accessibilityLabel("Page précédente")
            Spacer()
            if model.loader.isLoading { ProgressView() } else { Text("Page \(model.currentPage)").monospacedDigit() }
            Spacer()
            Button { Task { await model.goToNextPage() } } label: { Image(systemName: "chevron.right") }
                .disabled(!model.canGoToNext)
                .accessibilityLabel("Page suivante")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// HFR's confirmation of a new topic, above the list.
private struct TopicSentBanner: View {
    let text: String
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
            Text(text).scaledFont(.subheadline)
            Spacer()
            Button(action: close) { Image(systemName: "xmark") }
                .accessibilityLabel("Masquer")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}
