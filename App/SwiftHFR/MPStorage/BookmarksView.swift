import HFRModels
import SwiftUI

// Port of HFRswift/Swift/BookmarksPlusView.swift (BookmarksPlusView) @ 87fe0d1c. Differences: the rows are the app's own
// (title, author, date, as legacy's `TopicListRowView` call); « Connectez-vous » when no account is current (legacy
// « MPStorage indisponible »); the error is LOT-130's sentence in the status colour. GAP-040. #1107: the list look of every list
// (`listLook`); the selected row keeps its accent background in both looks.
/// Plus › Bookmarks (LOT-132): the account's bookmarks, newest first. A row opens its message beside the list on the
/// regular-width iPad (#1089), or on the Plus stack; a swipe deletes it.
struct BookmarksView: View {
    @State private var model: BookmarksModel
    let environment: AppEnvironment
    @Environment(\.openTopicInDetail) private var openInDetail
    /// The reader a row pushed on the Plus stack (no detail column).
    @State private var pushed: TopicReaderModel?
    @Environment(ExperimentalSettings.self) private var experimental: ExperimentalSettings?

    init(mpStorage: MPStorageSyncModel?, selection: BookmarkSelection, environment: AppEnvironment) {
        _model = State(initialValue: BookmarksModel(mpStorage: mpStorage, selection: selection))
        self.environment = environment
    }

    var body: some View {
        List {
            switch model.state {
            case .signedOut:
                Text("Connectez-vous pour voir vos bookmarks.").foregroundStyle(.secondary)
            case .notSyncing:
                VStack(alignment: .leading, spacing: 8) {
                    Label("Stockage MP désactivé", systemImage: "tray").scaledFont(.headline)
                    Text("Activez « Activer le stockage MP » dans Réglages pour récupérer vos bookmarks.")
                        .scaledFont(.footnote).foregroundStyle(.secondary)
                }
            case .syncing:
                listContent
            }
        }
        .listLook()
        .navigationTitle("Bookmarks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.state == .syncing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Label { Text("Actualiser") } icon: { ToolbarRefreshIcon(isLoading: model.isRefreshing) }
                    }
                    .disabled(model.isRefreshing)
                }
            }
        }
        .refreshable { await model.refresh() }
        .task { await model.load() }
        .navigationDestination(isPresented: isPushing) {
            if let pushed {
                TopicReaderView(model: pushed, services: environment.reader, composer: environment.composer)
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if let error = model.errorMessage {
            StatusLabel(text: "Erreur : \(error)", symbol: "exclamationmark.triangle.fill", tint: AccessibleColors.errorText)
        }
        let bookmarks = model.bookmarks
        if bookmarks.isEmpty {
            Text("Aucun bookmark").foregroundStyle(.secondary)
        } else {
            ForEach(bookmarks) { bookmark in
                Button { open(bookmark) } label: { BookmarkRow(bookmark: bookmark) }
                    // EXPERIMENTAL(denseRows, #1107): the dense look's clear row replaces the card's.
                    .listRowBackground(
                        isSelected(bookmark) ? Color.accentColor.opacity(0.15)
                            : ListLook.current(experimental) == .dense ? DenseListLook.rowBackground : nil
                    )
                    .accessibilityAddTraits(isSelected(bookmark) ? .isSelected : [])
            }
            .onDelete { offsets in
                let removed = offsets.map { bookmarks[$0] }
                Task {
                    for bookmark in removed {
                        let wasOpen = await model.delete(bookmark)
                        // Legacy clears the detail column when the bookmark it shows is deleted (`MainWindow.swift:2266-2271`).
                        if wasOpen { openInDetail?.close() }
                    }
                }
            }
        }
    }

    /// Selected only while it shows beside the list.
    private func isSelected(_ bookmark: MPStorageBookmark) -> Bool {
        openInDetail != nil && model.selectedID == bookmark.id
    }

    private var isPushing: Binding<Bool> {
        Binding(get: { pushed != nil }, set: { if !$0 { pushed = nil } })
    }

    private func open(_ bookmark: MPStorageBookmark) {
        guard let target = BookmarkList.target(of: bookmark) else { return }
        model.didOpen(bookmark)
        let title = BookmarkList.title(of: bookmark)
        if let openInDetail {
            openInDetail(target, title: title)
        } else {
            pushed = TopicReaderModel(
                target: target, title: title, source: environment.topicPages, renderOptions: environment.reader.settings.renderOptions
            )
        }
    }
}

/// One bookmark: its title, the author on the left and the date on the right (`BookmarksPlusView.swift:191-203`).
private struct BookmarkRow: View {
    let bookmark: MPStorageBookmark

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(BookmarkList.title(of: bookmark)).scaledFont(.headline).foregroundStyle(.primary)
            HStack {
                Text(bookmark.author)
                Spacer()
                Text(BookmarkList.dateText(of: bookmark))
            }
            .scaledFont(.footnote)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
