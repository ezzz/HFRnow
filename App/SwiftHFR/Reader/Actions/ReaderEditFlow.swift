import SwiftUI

// Port of HFRswift/Swift/MessagesView.swift (the `ProgressView` of a prefill, `:4472`; the alerts "Edition impossible", "Supprimer ce
// message ?" and "Suppression impossible", `:4618-4640`; the composer's full-screen cover) @ 2440d79. Differences: GAP-096, GAP-097; the
// composer is the reader's sheet, as a reply's (LOT-084).
/// The screens of "Editer" and "Supprimer" (LOT-088), all driven by `MessageWriteModel`. No branch on `writes`: it arrives after the
/// first render, and a branch would rebuild the reader's web view.
struct ReaderEditFlow: ViewModifier {
    let writes: MessageWriteModel?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let progress = writes?.progress {
                    // Floats over the page (LOT-185: glass for floating elements).
                    ProgressView(progress).padding().glassEffect(in: .rect(cornerRadius: 12))
                }
            }
            .sheet(item: Binding(get: { writes?.editor }, set: { writes?.editor = $0 })) { composer in
                // The reader suspends its page's taps while `editor` is set (`TopicReaderView`, #653).
                ReplyComposerView(model: composer, pageScrolls: true) { reason in
                    guard case .edit(let target) = composer.target else { return }
                    Task { await writes?.editorDidClose(reason, post: target.post) }
                }
            }
            .alert(
                "Supprimer ce message ?",
                isPresented: Binding(get: { writes?.pendingDelete != nil }, set: { if !$0 { writes?.pendingDelete = nil } }),
                presenting: writes?.pendingDelete
            ) { target in
                Button("Non", role: .cancel) {}
                Button("Oui", role: .destructive) { Task { await writes?.confirmDelete(target) } }
            } message: { _ in
                Text("Cette action est définitive.")
            }
            .alert(
                writes?.failure?.title ?? "",
                isPresented: Binding(get: { writes?.failure != nil }, set: { if !$0 { writes?.failure = nil } }),
                presenting: writes?.failure
            ) { failure in
                if let retry = failure.retry {
                    Button("Réessayer") { Task { await writes?.openEditor(retry) } }
                }
                Button("OK", role: .cancel) {}
            } message: { failure in
                Text(failure.message)
            }
    }
}
