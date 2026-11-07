import HFRModels
import SwiftUI
import UIKit

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
    /// Opens a row's topic at a page its menu names (LOT-125); nil hides those entries.
    var open: ((TopicSummary, TopicOpening) -> Void)?
    @State private var newTopic: ReplyComposerModel?
    /// The row whose "Page numéro…" prompt is shown.
    @State private var pagePrompt: TopicSummary?
    @State private var pageText = ""

    var body: some View {
        let loader = model.loader
        List(selection: $selection) {
            if loader.value != nil {
                ForEach(model.displayedGroups) { group in
                    if let title = group.title {
                        Section {
                            if !group.isCollapsed { rows(group.topics) }
                        } header: {
                            header(group, title: title)
                        }
                    } else {
                        rows(group.topics)
                    }
                }
            }
        }
        .navigationTitle(model.source.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay { overlay(loader) }
        .safeAreaBar(edge: .top) {
            VStack(spacing: 8) {
                if let confirmation = model.sentConfirmation {
                    TopicSentBanner(text: confirmation, close: model.clearSentConfirmation)
                }
                if let problem = model.favorites?.storeProblem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error = loader.error, loader.value != nil {
                    LoadFailureBanner(error: error, retry: model.retry)
                }
            }
        }
        .toolbar {
            if model.source.isPaged, loader.value != nil { PageBar(model: model) }
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
        .alert(
            "Action impossible", isPresented: Binding(get: { model.actionFailure != nil }, set: { if !$0 { model.clearActionFailure() } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionFailure ?? "")
        }
        .alert(
            "Page numéro", isPresented: Binding(get: { pagePrompt != nil }, set: { if !$0 { pagePrompt = nil } }),
            presenting: pagePrompt
        ) { topic in
            TextField("Page", text: $pageText).keyboardType(.numberPad)
            Button("Annuler", role: .cancel) {}
            Button("Aller") {
                let number = Int(pageText.trimmingCharacters(in: .whitespaces)) ?? 0
                if let opening = TopicQuickActions.page(number, of: topic) { open?(topic, opening) }
            }
        } message: { topic in
            Text("Entre 1 et \(topic.pageCount)")
        }
    }

    private func rows(_ topics: [TopicSummary]) -> some View {
        ForEach(topics) { topic in
            let isSuper = model.isSuperFavorite(topic)
            TopicRowView(topic: topic, isSuperFavorite: isSuper, markedRead: model.isMarkedRead(topic), showsFlag: model.hasFlag(topic))
                .tag(topic)
                .listRowBackground(isSuper ? Color.orange.opacity(0.12) : nil)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if model.canMarkRead(topic) {
                        Button { model.markRead(topic) } label: { Label("Lu", systemImage: "checkmark") }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if model.canRemoveFlag(topic) { removeButton(topic) }
                }
                .accessibilityActions {
                    // The swipes, for VoiceOver (a swipe is not reachable there).
                    if model.canMarkRead(topic) { Button("Lu") { model.markRead(topic) } }
                    if model.canRemoveFlag(topic), !model.isRemovingFlag(topic) {
                        Button("Supprimer") { Task { await model.removeFlag(topic) } }
                    }
                }
                .contextMenu { menu(topic, isSuper: isSuper) }
        }
    }

    /// "Supprimer" (legacy trailing swipe and menu entry): "Suppression…" and disabled while the removal is in flight.
    private func removeButton(_ topic: TopicSummary) -> some View {
        let removing = model.isRemovingFlag(topic)
        return Button(role: .destructive) {
            Task { await model.removeFlag(topic) }
        } label: {
            Label(removing ? "Suppression…" : "Supprimer", systemImage: removing ? "hourglass" : "trash")
        }
        .disabled(removing)
    }

    /// The row menu, in legacy order: the quick actions, then Lu, super favourite, Supprimer and the post filter.
    @ViewBuilder
    private func menu(_ topic: TopicSummary, isSuper: Bool) -> some View {
        if let open {
            if let opening = TopicQuickActions.firstPage(of: topic) {
                Button("Première page", systemImage: "backward.end") { open(topic, opening) }
            }
            if let opening = TopicQuickActions.lastPage(of: topic) {
                Button("Dernière page", systemImage: "forward.end") { open(topic, opening) }
            }
            if let opening = TopicQuickActions.lastReply(of: topic, in: model.source) {
                Button("Dernière réponse", systemImage: "text.append") { open(topic, opening) }
            }
            Button("Page numéro…", systemImage: "number") {
                pageText = "\(TopicQuickActions.suggestedPage(of: topic))"
                pagePrompt = topic
            }
        }
        if let link = TopicQuickActions.link(of: topic) {
            Button("Copier le lien", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = link.absoluteString
                AccessibilityNotification.Announcement("Lien copié").post()
            }
        }
        Divider()
        if model.canMarkRead(topic) {
            Button("Lu", systemImage: "checkmark") { model.markRead(topic) }
        }
        if let favorites = model.favorites, favorites.canMarkSuperFavorites, topic.topicID != nil {
            Button(isSuper ? "Retirer des super favoris" : "Ajouter aux super favoris", systemImage: "star.circle") {
                Task { await favorites.toggleSuperFavorite(topic) }
            }
        }
        if model.canRemoveFlag(topic) { removeButton(topic) }
        if model.source == .favorites, let filtering, topic.topicID != nil {
            Divider()
            Button { filtering.start(opening: topic) } label: {
                Label("Filtrer les posts", systemImage: "line.3.horizontal.decrease.circle")
            }
            .disabled(filtering.isBusy)
        }
    }

    /// A category header with its topic count and, when the section has topics, the fold chevron (legacy `sectionHeader`).
    private func header(_ group: TopicGroup, title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(group.topics.count)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            if group.isCollapsible, let favorites = model.favorites {
                Button {
                    Task { await favorites.toggleCollapsed(group.id) }
                } label: {
                    Image(systemName: group.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .frame(width: 32, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(group.isCollapsed ? "Déplier \(title)" : "Plier \(title)")
            }
        }
    }

    @ViewBuilder
    private func overlay(_ loader: ContentLoader<TopicListContent>) -> some View {
        if let content = loader.value {
            if content.isEmpty, let reason = content.emptyReason {
                EmptyListView(reason: reason, refresh: model.refresh)
            } else if model.allSectionsHidden, let favorites = model.favorites {
                AllSectionsCollapsedView(options: favorites)
            }
        } else if let error = loader.error {
            LoadFailureView(error: error, retry: model.retry)
        } else if loader.isLoading {
            ProgressView("Chargement des sujets")
        }
    }
}

/// Every section is folded and the options hide folded sections (legacy `allSectionsCollapsedState`).
private struct AllSectionsCollapsedView: View {
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
private struct PageBar: ToolbarContent {
    let model: TopicListModel

    var body: some ToolbarContent {
        PagerToolbar(
            first: .init(enabled: model.canGoToPrevious) { Task { await model.goToFirstPage() } },
            previous: .init(enabled: model.canGoToPrevious) { Task { await model.goToPreviousPage() } },
            next: .init(enabled: model.canGoToNext) { Task { await model.goToNextPage() } },
            last: nil,
            status: model.loader.isLoading ? .loading : .page(model.currentPage)
        )
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
