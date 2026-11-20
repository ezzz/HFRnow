import SwiftUI

// Port of HFRswift/Swift/MessagesView.swift (the AQ prompt `:4506-4543`, MessagePopupPromptSheet `:453-530`, the AQ sheet `:5445-5473`)
// @ 87fe0d1c. Differences: the first-use notice N1 comes first; a message that an AQ of someone else holds offers « Plussoyer »
// instead of a refusal (#224); the sheet closes at once and the reader's banner says how it went. GAP-069.
/// The questions of « AQ » (LOT-134): the notice, the title of a new alert, the addition to an existing one.
struct ReaderQualityAlertFlow: ViewModifier {
    let alerts: QualityAlertActionModel?

    func body(content: Content) -> some View {
        content
            .alert("Alerte Qualitay", isPresented: noticeShown, presenting: notice) { draft in
                // The draft comes from the alert: SwiftUI clears the presenting state before the button runs (LOT-087).
                Button("Continuer") { alerts?.answerNotice(true, for: draft) }
                Button("Annuler", role: .cancel) { alerts?.answerNotice(false, for: draft) }
            } message: { _ in
                Text(alerts?.noticeMessage ?? "")
            }
            .alert("Alerte Qualitay", isPresented: additionShown, presenting: addition) { draft in
                Button("Plussoyer") { Task { await alerts?.add(draft) } }
                Button("Annuler", role: .cancel) {}
            } message: { draft in
                Text("Ce message est déjà signalé dans « \(draft.existing?.title ?? "") ». L'ajouter à cette alerte ?")
            }
            .sheet(item: titleShown) { draft in
                QualityAlertTitleSheet(draft: draft) { title in Task { await alerts?.create(draft, title: title) } }
                    .presentationDetents([.medium])
            }
    }

    private var notice: QualityAlertActionModel.Draft? {
        if case .notice(let draft)? = alerts?.prompt { draft } else { nil }
    }

    private var addition: QualityAlertActionModel.Draft? {
        if case .addition(let draft)? = alerts?.prompt { draft } else { nil }
    }

    private var noticeShown: Binding<Bool> {
        Binding(get: { notice != nil }, set: { if !$0, notice != nil { alerts?.prompt = nil } })
    }

    private var additionShown: Binding<Bool> {
        Binding(get: { addition != nil }, set: { if !$0, addition != nil { alerts?.prompt = nil } })
    }

    private var titleShown: Binding<QualityAlertActionModel.Draft?> {
        Binding(
            get: { if case .title(let draft)? = alerts?.prompt { draft } else { nil } },
            set: { if $0 == nil, case .title? = alerts?.prompt { alerts?.prompt = nil } }
        )
    }
}

/// Legacy's prompt: the question, a title field, « Annuler » and « Créer » (off while the title is blank).
private struct QualityAlertTitleSheet: View {
    let draft: QualityAlertActionModel.Draft
    let create: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var title = ""
    @State private var isAskingDiscard = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Group {
                        Text("Créer une Alerte Qualitay sur le post de \(draft.author) ?").scaledFont(.callout).foregroundStyle(.secondary)
                        TextField("Titre de l'alerte", text: $title)
                            .textInputAutocapitalization(.sentences)
                            .focused($focused)
                            .submitLabel(.done)
                            .onSubmit(submit)
                    }.themedListRow()
                }
            }
            .themedListScreen()
            .navigationTitle("AQ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { if DiscardConfirmation.hasText(title) { isAskingDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Créer", action: submit).disabled(isBlank) }
            }
            .task { focused = true }
        }
        // A typed title is not thrown away without asking (#1169).
        .discardConfirmation(
            "Abandonner cette alerte ?", hasChanges: DiscardConfirmation.hasText(title), isAsking: $isAskingDiscard
        ) { dismiss() }
    }

    private var isBlank: Bool { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func submit() {
        guard !isBlank else { return }
        create(title)
    }
}

extension QualityAlertActionModel {
    /// The model for an appearance's install: the one in progress when a question is open, else a fresh one over the current
    /// services; nil without services (the caller passes none for a saved copy: no account behind it).
    static func reusing(
        _ current: QualityAlertActionModel?, services: QualityAlertServices?, page title: @escaping @MainActor () -> String?,
        confirm: @escaping @MainActor (String) -> Void
    ) -> QualityAlertActionModel? {
        guard let services else { return nil }
        if let current, !current.isIdle { return current }
        return QualityAlertActionModel(services: services, topicTitle: title, confirm: confirm)
    }
}
