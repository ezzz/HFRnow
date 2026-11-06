import SwiftUI

/// The reader's "Enregistrer hors ligne" menu and the progress banner (LOT-139). Hidden for a private conversation (it cannot
/// be read without the session) and in the offline reader itself.
struct ReaderOfflineSave: ViewModifier {
    /// How many pages "this page and the next ones" saves, this one included. Legacy read an `offline_max_pages` setting nothing
    /// ever wrote (`OfflineStorage.m:145-294`, commented out): the number is LOT-139's choice, listed in the PR.
    static let pagesInBatch = 5

    let model: TopicReaderModel
    @State private var saver: OfflineSaveModel?
    /// The save asked for; the task below runs it, and ends with the screen (not when the screen is only covered).
    @State private var request: SaveRequest?

    private struct SaveRequest: Equatable {
        let id = UUID()
        let page: ReaderPage
        let count: Int
    }

    init(model: TopicReaderModel, offline: OfflineServices?) {
        self.model = model
        _saver = State(initialValue: offline.map { OfflineSaveModel(store: $0.store, fetcher: $0.fetcher) })
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                if let saver, !model.isPrivateConversation, let page = model.page {
                    ToolbarItem(placement: .secondaryAction) { menu(saver, page: page) }
                }
            }
            .safeAreaInset(edge: .top) {
                if let saver, saver.state != .idle { OfflineSaveBanner(saver: saver) }
            }
            .task(id: request) {
                guard let saver, let request else { return }
                await saver.save(page: request.page, count: request.count, fallbackTitle: model.initialTitle)
            }
    }

    @ViewBuilder
    private func menu(_ saver: OfflineSaveModel, page: ReaderPage) -> some View {
        if saver.isSaving {
            Button("Arrêter l’enregistrement", systemImage: "stop.circle") { saver.cancel() }
        } else {
            Button("Enregistrer cette page hors ligne", systemImage: "arrow.down.circle") {
                request = SaveRequest(page: page, count: 1)
            }
            // Disabled on the last page: there are no following pages to save.
            Button("Enregistrer cette page et les \(Self.pagesInBatch - 1) suivantes", systemImage: "arrow.down.circle.fill") {
                request = SaveRequest(page: page, count: Self.pagesInBatch)
            }
            .disabled(page.currentPage >= page.maxPage)
        }
    }
}

extension View {
    /// Adds the offline save menu of `model`'s topic.
    func offlineSave(model: TopicReaderModel, offline: OfflineServices?) -> some View {
        modifier(ReaderOfflineSave(model: model, offline: offline))
    }
}

/// One line on the state of a save.
private struct OfflineSaveBanner: View {
    let saver: OfflineSaveModel

    var body: some View {
        HStack(spacing: 8) {
            if saver.isSaving { ProgressView() }
            Text(OfflineSaveText.text(for: saver.state)).scaledFont(.footnote)
            Spacer()
            if !saver.isSaving { Button("Fermer", systemImage: "xmark") { saver.dismiss() }.labelStyle(.iconOnly) }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }
}

/// The French line of each state.
enum OfflineSaveText {
    static func text(for state: OfflineSaveModel.State) -> String {
        switch state {
        case .idle: ""
        case .saving(let done, let total): "Enregistrement hors ligne : \(done) sur \(total)"
        case .finished(let saved): saved == 1 ? "1 page enregistrée hors ligne" : "\(saved) pages enregistrées hors ligne"
        case .stopped(let saved): "Enregistrement arrêté : \(savedPages(saved))"
        case .failed(let message, let saved): saved == 0 ? message : "\(message) (\(savedPages(saved)))"
        }
    }

    private static func savedPages(_ count: Int) -> String { count > 1 ? "\(count) pages enregistrées" : "\(count) page enregistrée" }
}
