import HFRModels
import SwiftUI

/// The Messages list: the member's conversations, paged, with pull to refresh. A tap selects a row; the reader shows it.
struct MessageListView: View {
    let model: MessageListModel

    var body: some View {
        let loader = model.loader
        List(selection: Binding(get: { model.selected }, set: { model.selected = $0 })) {
            if let content = loader.value {
                ForEach(content.threads) { thread in
                    MessageRowView(thread: thread, isUnread: model.isUnread(thread)).tag(thread)
                }
            }
        }
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { overlay(loader) }
        .safeAreaInset(edge: .top) {
            if let error = loader.error, loader.value != nil {
                LoadFailureBanner(error: error, retry: model.retry)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let content = loader.value, content.page > 1 || content.hasNext { MessagePageBar(model: model) }
        }
        .refreshable { await model.refresh() }
        .task { await model.onAppear() }
    }

    @ViewBuilder
    private func overlay(_ loader: ContentLoader<MessageListContent>) -> some View {
        if let content = loader.value {
            if content.threads.isEmpty, let reason = content.emptyReason { EmptyMessagesView(reason: reason, refresh: model.refresh) }
        } else if let error = loader.error {
            LoadFailureView(error: error, retry: model.retry)
        } else if loader.isLoading {
            ProgressView("Chargement des messages")
        }
    }
}

private struct EmptyMessagesView: View {
    let reason: EmptyReason
    let refresh: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            if let message { Text(message) }
        } actions: {
            Button("Actualiser") { Task { await refresh() } }
        }
    }

    private var title: String {
        switch reason {
        case .nothing: "Aucun message privé"
        case .signInRequired: "Connexion requise"
        case .notice: "Rien à afficher"
        }
    }

    private var symbol: String {
        if case .signInRequired = reason { "lock" } else { "envelope" }
    }

    private var message: String? {
        switch reason {
        case .nothing: nil
        case .signInRequired(let notice): notice ?? "Connectez-vous pour lire vos messages privés."
        case .notice(let notice): notice
        }
    }
}

/// Previous / next controls. Only "a next page exists" is known: the pager is a window, never a total.
private struct MessagePageBar: View {
    let model: MessageListModel

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
