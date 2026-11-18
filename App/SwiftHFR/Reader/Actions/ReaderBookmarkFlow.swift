import SwiftUI

// Port of HFRswift/Swift/MessagesView.swift (MessagePopupPromptSheet `:453-530`, the bookmark sheet `:5475-5496`) @ 87fe0d1c.
// Differences: the consent question of an account that never chose (ADR 0013 §7); the sheet closes at once and the reader's
// banner says how the creation went (the write is local first, GAP-183). GAP-068.
/// The questions of « Bookmark » (LOT-132): the consent alert, then the title sheet. Nothing shows without a model.
struct ReaderBookmarkFlow: ViewModifier {
    let bookmarks: BookmarkActionModel?

    func body(content: Content) -> some View {
        content
            .alert("Stockage MP", isPresented: consentShown, presenting: bookmarks?.pendingConsent) { draft in
                // The draft comes from the alert: SwiftUI clears the presenting state before the button runs (LOT-087).
                Button("Activer") { Task { await bookmarks?.answerConsent(true, for: draft) } }
                Button("Annuler", role: .cancel) { Task { await bookmarks?.answerConsent(false, for: draft) } }
            } message: { _ in
                Text(BookmarkActionModel.consentQuestion)
            }
            .sheet(item: promptShown) { draft in
                BookmarkTitleSheet(draft: draft) { title in Task { await bookmarks?.create(draft, title: title) } }
                    .presentationDetents([.medium])
            }
    }

    private var consentShown: Binding<Bool> {
        Binding(get: { bookmarks?.pendingConsent != nil }, set: { if !$0 { bookmarks?.pendingConsent = nil } })
    }

    private var promptShown: Binding<BookmarkActionModel.Draft?> {
        Binding(get: { bookmarks?.prompt }, set: { bookmarks?.prompt = $0 })
    }
}

/// Legacy's prompt: the question, a title field, « Annuler » and « Créer », the latter off while the title is blank.
private struct BookmarkTitleSheet: View {
    let draft: BookmarkActionModel.Draft
    let create: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var title = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Créer un bookmark sur le post de \(draft.author) ?").font(.callout).foregroundStyle(.secondary)
                    TextField("Ajoutez un titre", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(submit)
                }
            }
            .navigationTitle("Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Créer", action: submit).disabled(isBlank) }
            }
            .task { focused = true }
        }
    }

    private var isBlank: Bool { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func submit() {
        guard !isBlank else { return }
        create(title)
    }
}
