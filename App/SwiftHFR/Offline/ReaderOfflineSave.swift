import SwiftUI

/// The reader's offline save progress banner (LOT-139); its menu items are `ReaderOfflineMenuItems`, placed in the "…" overflow
/// by `ReaderOverflowToolbar` (#645). Not offered for a private conversation (it cannot be read without the session) nor in
/// the offline reader itself.
struct ReaderOfflineSave: ViewModifier {
    /// How many pages "this page and the next ones" saves, this one included. Legacy read an `offline_max_pages` setting nothing
    /// ever wrote (`OfflineStorage.m:145-294`, commented out): the number is LOT-139's choice, listed in the PR.
    static let pagesInBatch = 5

    let model: TopicReaderModel
    /// Owned by the reader view, which stops its run when the member really leaves (`TopicReaderView.onDisappear`).
    let saver: OfflineSaveModel?

    func body(content: Content) -> some View {
        content
            .safeAreaBar(edge: .top) {
                if let saver, saver.state != .idle { OfflineSaveBanner(saver: saver) }
            }
    }

    /// Whether the overflow offers it: none under an open composer (#653: the "…" overflow stays shut).
    static func isOffered(model: TopicReaderModel, saver: OfflineSaveModel?) -> Bool {
        saver != nil && !model.isPrivateConversation && model.page != nil && !model.suspendsPageInteractions
    }
}

extension View {
    /// Adds the offline save banner of `model`'s topic.
    func offlineSave(model: TopicReaderModel, saver: OfflineSaveModel?) -> some View {
        modifier(ReaderOfflineSave(model: model, saver: saver))
    }
}

/// The offline save items of the "…" overflow. A view of its own, so `saver.isSaving` is read here and a saved page does not
/// re-run the reader's body.
struct ReaderOfflineMenuItems: View {
    let saver: OfflineSaveModel
    let model: TopicReaderModel
    let page: ReaderPage

    var body: some View {
        if saver.isSaving {
            Button("Arrêter l’enregistrement", systemImage: "stop.circle") { saver.cancel() }
        } else {
            Button("Enregistrer cette page hors ligne", systemImage: "arrow.down.circle") {
                saver.start(page: page, count: 1, fallbackTitle: model.initialTitle)
            }
            // Disabled on the last page: there are no following pages to save.
            let batch = ReaderOfflineSave.pagesInBatch
            Button("Enregistrer cette page et les \(batch - 1) suivantes", systemImage: "arrow.down.circle.fill") {
                saver.start(page: page, count: batch, fallbackTitle: model.initialTitle)
            }
            .disabled(page.currentPage >= page.maxPage)
        }
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
