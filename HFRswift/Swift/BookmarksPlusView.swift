//
//  BookmarksPlusView.swift
//  HFRswift
//
//  SwiftUI migration of Plus > Bookmarks root list
//

import SwiftUI
import Combine

@MainActor
final class BookmarksPlusViewModel: ObservableObject {
    @Published var bookmarks: [Bookmark] = []
    @Published var isRefreshing = false
    @Published var errorMessage: String?

    private let storage: LegacyMPStorageManaging
    private var refreshFallbackWorkItem: DispatchWorkItem?
    private var shouldTriggerRefreshHaptic = false

    init(storage: LegacyMPStorageManaging = ObjCMPStorageBridge.shared) {
        self.storage = storage
    }

    deinit {
        refreshFallbackWorkItem?.cancel()
    }

    var isStorageEnabled: Bool {
        UserDefaults.standard.bool(forKey: "mpstorage_active")
    }

    func loadBookmarks() {
        guard storage.isAvailable else {
            bookmarks = []
            errorMessage = "MPStorage indisponible"
            return
        }

        storage.parseBookmarks()
        let count = max(storage.bookmarksCount(), 0)
        var loaded: [Bookmark] = []
        loaded.reserveCapacity(count)

        if count > 0 {
            for index in 0..<count {
                if let bookmark = storage.bookmark(at: index) {
                    loaded.append(bookmark)
                }
            }
        }

        bookmarks = loaded
        if errorMessage != nil {
            errorMessage = nil
        }
    }

    func refreshRemoteBookmarks(shouldTriggerHaptic: Bool = false) {
        guard storage.isAvailable else { return }
        guard isStorageEnabled else {
            errorMessage = "Activez le stockage MP dans Réglages pour synchroniser les bookmarks."
            return
        }

        errorMessage = nil
        shouldTriggerRefreshHaptic = shouldTriggerHaptic
        isRefreshing = true
        storage.reloadAsynchronously()

        refreshFallbackWorkItem?.cancel()
        let fallback = DispatchWorkItem { [weak self] in
            guard let self, self.isRefreshing else { return }
            self.finishRefresh()
        }
        refreshFallbackWorkItem = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: fallback)
    }

    func handleStorageUpdateSignal() {
        if isRefreshing {
            finishRefresh()
        } else {
            loadBookmarks()
        }
    }

    func delete(at offsets: IndexSet) {
        guard storage.isAvailable else { return }
        let targets = offsets.compactMap { index in
            bookmarks.indices.contains(index) ? bookmarks[index] : nil
        }
        for bookmark in targets {
            _ = storage.removeBookmark(bookmark)
        }
        loadBookmarks()
    }

    private func finishRefresh() {
        refreshFallbackWorkItem?.cancel()
        refreshFallbackWorkItem = nil
        isRefreshing = false
        loadBookmarks()
        if shouldTriggerRefreshHaptic {
            shouldTriggerRefreshHaptic = false
            AppHaptics.refreshCompleted()
        }
    }
}

struct BookmarksPlusView: View {
    @StateObject private var viewModel: BookmarksPlusViewModel
    @AppStorage("mpstorage_last_rw") private var mpStorageLastAccess = "-"
    @State private var hasLoaded = false
    private let selectedTopicID: TopicNavigationID?
    private let onSelectTopic: ((TopicNavigationTarget) -> Void)?
    private let onDeleteTopic: ((TopicNavigationID) -> Void)?

    @MainActor
    init(
        viewModel: BookmarksPlusViewModel? = nil,
        selectedTopicID: TopicNavigationID? = nil,
        onSelectTopic: ((TopicNavigationTarget) -> Void)? = nil,
        onDeleteTopic: ((TopicNavigationID) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel ?? BookmarksPlusViewModel())
        self.selectedTopicID = selectedTopicID
        self.onSelectTopic = onSelectTopic
        self.onDeleteTopic = onDeleteTopic
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "dd/MM/yyyy 'a' HH:mm"
        return formatter
    }()

    private func makeTopic(from bookmark: Bookmark) -> Topic {
        let topic = Topic()
        let label = (bookmark.sLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        topic._aTitle = label.isEmpty ? "Bookmark" : label
        let url = bookmark.getUrl() ?? ""
        topic.aURL = url
        topic.aURLOfLastPage = url
        topic.curTopicPage = 1
        topic.maxTopicPage = 1
        return topic
    }

    private func dateLabel(for bookmark: Bookmark) -> String {
        guard let date = bookmark.dateBookmarkCreation else { return "-" }
        return Self.dateFormatter.string(from: date)
    }

    private func deleteBookmarks(at offsets: IndexSet) {
        let deletedTopicIDs = offsets.compactMap { index -> TopicNavigationID? in
            guard viewModel.bookmarks.indices.contains(index) else { return nil }
            return TopicNavigationIdentity.id(
                for: makeTopic(from: viewModel.bookmarks[index]),
                context: .generic
            )
        }
        viewModel.delete(at: offsets)
        deletedTopicIDs.forEach { onDeleteTopic?($0) }
    }

    var body: some View {
        List {
            if !viewModel.isStorageEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Stockage MP désactivé", systemImage: "tray")
                        .font(.headline)
                    Text("Activez \"Activer le stockage MP\" dans Réglages pour récupérer vos bookmarks.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text("Erreur : \(errorMessage)")
                    .foregroundStyle(.red)
            }

            if viewModel.bookmarks.isEmpty {
                Text("Aucun bookmark")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(viewModel.bookmarks.enumerated()), id: \.offset) { _, bookmark in
                    let topic = makeTopic(from: bookmark)
                    TopicListRowView(
                        topic: topic,
                        isVisited: false,
                        titleFont: .headline,
                        titleOverride: (bookmark.sLabel ?? "").isEmpty
                            ? "Bookmark"
                            : (bookmark.sLabel ?? "Bookmark"),
                        leadingBottomText: bookmark.sAuthorPost,
                        trailingBottomText: dateLabel(for: bookmark),
                        openContext: .generic,
                        selectedTopicID: selectedTopicID,
                        onSelectTarget: onSelectTopic
                    )
                }
                .onDelete(perform: deleteBookmarks)
            }
        }
        .navigationTitle("Bookmarks")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isRefreshing {
                    ProgressView()
                } else {
                    Button("Actualiser", systemImage: "arrow.clockwise") {
                        AppHaptics.refreshStarted()
                        viewModel.refreshRemoteBookmarks(shouldTriggerHaptic: true)
                    }
                }
            }
        }
        .onAppear {
            if !hasLoaded {
                viewModel.loadBookmarks()
                hasLoaded = true
            }
        }
        .onChange(of: mpStorageLastAccess) { _, _ in
            viewModel.handleStorageUpdateSignal()
        }
        .refreshable {
            viewModel.refreshRemoteBookmarks(shouldTriggerHaptic: true)
        }
    }
}

#Preview("Bookmarks Plus") {
    NavigationStack {
        BookmarksPlusView()
    }
}
