import HFRModels
import HFRStorage
import SwiftUI

// Port of none @ 2440d79: legacy has no offline list (`OfflineStorage` archives a set no screen shows, `PageViewController.m:154` is
// the only caller). Entry point and list are LOT-139's choice for GAP-180; the operator confirms the place in the PR.
/// The saved topics: open one to read it without network, swipe to delete, "Tout supprimer", and the size they take.
struct OfflineTopicsView: View {
    let services: ReaderServices
    @State private var model: OfflineTopicsModel
    @State private var opened: OfflineReaderTarget?
    @State private var confirmingDeleteAll = false

    init(offline: OfflineServices, services: ReaderServices) {
        self.services = services
        _model = State(initialValue: OfflineTopicsModel(services: offline))
    }

    var body: some View {
        List {
            if let message = model.errorMessage {
                Section { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            if model.topics.isEmpty, model.hasLoaded {
                ContentUnavailableView(
                    "Aucun sujet enregistré", systemImage: "arrow.down.circle",
                    description: Text(
                        "Dans un sujet, le menu « … » puis « Enregistrer cette page hors ligne » "
                            + "garde ses pages pour les lire sans réseau."
                    )
                )
                .listRowBackground(Color.clear)
            }
            ForEach(model.topics, id: \.topic) { topic in
                Button { opened = OfflineReaderTarget(topic: topic) } label: { OfflineTopicRow(topic: topic) }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Supprimer", role: .destructive) { Task { await model.remove(topic) } }
                    }
            }
            if !model.topics.isEmpty {
                Section {
                    LabeledContent("Espace utilisé", value: OfflineSize.text(model.sizeOnDisk))
                }
            }
        }
        .navigationTitle("Sujets hors ligne")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Tout supprimer", systemImage: "trash", role: .destructive) { confirmingDeleteAll = true }
                    .disabled(model.topics.isEmpty)
            }
        }
        .confirmationDialog("Supprimer tous les sujets enregistrés ?", isPresented: $confirmingDeleteAll, titleVisibility: .visible) {
            Button("Tout supprimer", role: .destructive) { Task { await model.removeAll() } }
        }
        .navigationDestination(item: $opened) { target in
            OfflineReaderScreen(topic: target.topic, model: model, services: services)
        }
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}

/// The selection of the list: a value, so the pushed screen builds its reader model once.
struct OfflineReaderTarget: Hashable, Identifiable {
    let topic: OfflineTopic
    var id: TopicID { topic.topic }

    static func == (left: Self, right: Self) -> Bool { left.id == right.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The reader of one saved topic: its model lives in the view's state, so a redraw never reloads the page. No composer, no
/// save menu (`offline: nil`), no "Favoris" (`flagActions: nil`), no reading position (it would record against the live topic).
private struct OfflineReaderScreen: View {
    let services: ReaderServices
    @State private var reader: TopicReaderModel

    init(topic: OfflineTopic, model: OfflineTopicsModel, services: ReaderServices) {
        var offlineServices = services
        offlineServices.offline = nil
        offlineServices.positions = nil
        // No write from a saved copy, as no reply (`composer: nil`): "Favoris" is hidden (LOT-125).
        offlineServices.flagActions = nil
        self.services = offlineServices
        _reader = State(initialValue: model.reader(for: topic, renderOptions: services.settings.renderOptions))
    }

    var body: some View {
        TopicReaderView(model: reader, services: services, composer: nil)
    }
}

private struct OfflineTopicRow: View {
    let topic: OfflineTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(topic.title.isEmpty ? "Sujet \(topic.topic.topic)" : topic.title).scaledFont(.body).lineLimit(2)
            Text("\(OfflinePageCount.text(topic.pages)) · enregistré \(topic.lastSavedAt.formatted(.relative(presentation: .named)))")
                .scaledFont(.footnote).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "3 pages" or "pages 4 à 8", from the saved page numbers.
enum OfflinePageCount {
    static func text(_ pages: [Int]) -> String {
        guard let first = pages.first, let last = pages.last else { return "aucune page" }
        if pages.count == 1 { return "page \(first)" }
        if last - first + 1 == pages.count { return "pages \(first) à \(last)" }
        return "\(pages.count) pages"
    }
}

/// A size in bytes, as the system writes it.
enum OfflineSize {
    static func text(_ bytes: Int) -> String {
        Int64(bytes).formatted(.byteCount(style: .file))
    }
}
