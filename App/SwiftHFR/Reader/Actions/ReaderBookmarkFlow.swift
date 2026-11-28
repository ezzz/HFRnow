import SwiftUI

// Port of HFRswift/Swift/MessagesView.swift (MessagePopupPromptSheet `:453-530`, the bookmark sheet `:5475-5496`) @ 87fe0d1c.
// Differences: the consent question of an account that never chose (ADR 0013 §7); the sheet closes at once and the reader's
// banner says how the creation went (the write is local first, GAP-183). GAP-068.
/// The questions of « Bookmark » (LOT-132): the consent alert, then the title sheet. Nothing shows without a model.
struct ReaderBookmarkFlow: ViewModifier {
    let bookmarks: BookmarkActionModel?

    func body(content: Content) -> some View {
        content
            .alert(AlertTitles.mpStorageQuestion, isPresented: consentShown, presenting: bookmarks?.pendingConsent) { draft in
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

/// Legacy's prompt: the question, a title field, « Annuler » and « Créer », the latter off while the title is blank or holds
/// an emoji the storage cannot keep (said under the field).
private struct BookmarkTitleSheet: View {
    let draft: BookmarkActionModel.Draft
    let create: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var title = ""
    @State private var isAskingDiscard = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ThemedRows {
                        Text("Créer un bookmark sur le post de \(draft.author) ?").scaledFont(.callout).foregroundStyle(.secondary)
                        TextField("Ajoute un titre", text: $title)
                            .textInputAutocapitalization(.sentences)
                            .focused($focused)
                            .submitLabel(.done)
                            .onSubmit(submit)
                    }
                } footer: {
                    Group {
                        // Said before « Créer », so the title is never lost to a refused write (LOT-062).
                        if let problem, !problem.isEmpty { Text(problem) }
                    }.themedSectionHeader()
                }
            }
            .themedListScreen()
            .navigationTitle("Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { if DiscardConfirmation.hasText(title) { isAskingDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Créer", action: submit).disabled(problem != nil) }
            }
            .task { focused = true }
        }
        // A typed title is not thrown away without asking (#1169).
        .discardConfirmation(
            "Abandonner ce bookmark ?", hasChanges: DiscardConfirmation.hasText(title), isAsking: $isAskingDiscard
        ) { dismiss() }
    }

    private var problem: String? { BookmarkActionModel.titleProblem(title) }

    private func submit() {
        guard problem == nil else { return }
        create(title)
    }
}
