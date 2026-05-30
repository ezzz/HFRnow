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

    @MainActor
    init(viewModel: BookmarksPlusViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? BookmarksPlusViewModel())
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
                    NavigationLink {
                        MessagesView(
                            topic: makeTopic(from: bookmark),
                            curPage: 1,
                            maxPage: 1,
                            separatorNewMessages: true
                        )
                        .toolbar(.hidden, for: .tabBar)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text((bookmark.sLabel ?? "").isEmpty ? "Bookmark" : (bookmark.sLabel ?? "Bookmark"))
                                .font(.headline)
                            Text(bookmark.sAuthorPost ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(dateLabel(for: bookmark))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete(perform: viewModel.delete)
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
