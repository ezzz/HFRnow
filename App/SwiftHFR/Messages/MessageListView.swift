import HFRModels
import SwiftUI

// Port of HFRswift/Swift/MPListView.swift (MPListView, group row `:773-780`) @ 2440d79. Differences: the "MP" / "MP multiples"
// switch is new (LOT-171, operator decision 2026-10-28).
/// The Messages list: the member's conversations, paged, with pull to refresh. A tap selects a row; the reader shows it.
struct MessageListView: View {
    let model: MessageListModel

    var body: some View {
        let loader = model.loader
        List(selection: Binding(get: { model.selected }, set: { model.selected = $0 })) {
            if loader.value != nil {
                ForEach(model.visibleThreads) { thread in
                    MessageRowView(thread: thread, isUnread: model.isUnread(thread)).tag(thread)
                }
            }
        }
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { overlay(loader) }
        .safeAreaInset(edge: .top) {
            if model.showsSegmentSwitch { MessageSegmentSwitch(model: model) }
        }
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
            if model.isSearchingSegment, model.visibleThreads.isEmpty {
                ProgressView("Recherche des \(model.segment.title)")
            } else if model.visibleThreads.isEmpty {
                EmptyMessagesView(
                    reason: content.emptyReason ?? .nothing, segment: model.display == .split ? model.segment : nil,
                    refresh: model.refresh
                )
            }
        } else if let error = loader.error {
            LoadFailureView(error: error, retry: model.retry)
        } else if loader.isLoading {
            ProgressView("Chargement des messages")
        }
    }
}

private struct EmptyMessagesView: View {
    let reason: EmptyReason
    /// The switch position when the list is split: the page may hold none of it though later pages exist.
    let segment: MPSegment?
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
        case .nothing:
            switch segment {
            case .group: "Aucun MP multiple"
            case .oneToOne: "Aucun MP individuel"
            case nil: "Aucun message privé"
            }
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

/// The "MP" / "MP multiples" switch of the split list, each segment with its own unread count (page-bounded).
private struct MessageSegmentSwitch: View {
    let model: MessageListModel

    var body: some View {
        Picker("Type de MP", selection: Binding(get: { model.segment }, set: { segment in
            model.segment = segment
            Task { await model.select(segment) }
        })) {
            ForEach(MPSegment.allCases, id: \.self) { segment in
                let unread = model.unreadCount(in: segment)
                Text(unread > 0 ? "\(segment.title) (\(unread))" : segment.title).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
