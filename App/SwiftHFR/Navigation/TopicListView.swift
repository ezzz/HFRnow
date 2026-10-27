import HFRModels
import SwiftUI

/// The middle column: the topics of the selected source, with pagination for forums.
struct TopicListView: View {
    let model: TopicListModel
    @Binding var selection: TopicSummary?

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
            if let error = loader.error, loader.value != nil {
                LoadFailureBanner(error: error, retry: model.retry)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.source.isPaged, loader.value != nil { PageBar(model: model) }
        }
        .refreshable { await model.refresh() }
        .task { await model.onAppear() }
    }

    private func rows(_ topics: [TopicSummary]) -> some View {
        ForEach(topics) { topic in
            TopicRowView(topic: topic).tag(topic)
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
