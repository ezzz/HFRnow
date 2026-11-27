import SwiftUI

// Port of HFRswift/Swift/MessagesView.swift (ModerationAlertComposerView, `:7415-7524`) @ 87fe0d1c. Differences: GAP-070; the
// sheet closes on an alert HFR did not confirm (`ModeratorAlertComposerModel`), and the swipe-down waits for a running send;
// a typed reason is not thrown away without asking (#1169, legacy `:7479-7484` closed at once).
/// The reason sheet "Alerte Modération" (LOT-135): legacy's warning, the reason, "Annuler" and "Envoyer".
struct ModeratorAlertComposerView: View {
    let model: ModeratorAlertComposerModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var isAskingDiscard = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(ModeratorAlertComposerModel.warning)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: Binding(get: { model.reason }, set: { model.reason = $0 }))
                        .focused($focused)
                        .scaledFont(.body)
                        .disabled(model.isSending)
                        .accessibilityLabel("Motif de l’alerte")
                    if model.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Décris le problème…")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                if model.isSending {
                    ProgressView("Envoi de l’alerte…").font(.footnote)
                }
            }
            .padding()
            .navigationTitle("Alerte Modération")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        if model.hasUnsavedReason { isAskingDiscard = true } else { dismiss() }
                    }
                    .disabled(model.isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Envoyer") { Task { await model.send() } }.disabled(!model.canSend)
                }
            }
        }
        // The swipe-down waits for a running send, and typed text is not thrown away without asking (#1169).
        .discardConfirmation(
            "Abandonner cette alerte ?", hasChanges: model.isSending || model.hasUnsavedReason, isAsking: $isAskingDiscard
        ) { dismiss() }
        .onAppear { focused = true }
        .alert(
            "Alerte impossible",
            isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.error ?? "")
        }
    }
}
