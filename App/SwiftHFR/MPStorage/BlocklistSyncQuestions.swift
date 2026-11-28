import SwiftUI

// Port of Classes/MPStorage.m (initOrResetMP:fromView:, the creation alert) @ 87fe0d1c. Differences: asked at the first
// blocklist write of an account that never chose, wherever the write was made (ADR 0013 §7), instead of at the switch-on
// only; one more question before it, as the write itself does not say it goes to the forum. GAP-182. The creation question
// is a « Oui »-selected choice with a confirmation before a « Non » (#1014).
/// The two questions of a first blocklist write (LOT-131): sync with MPStorage, then, when the account has no storage thread,
/// the legacy creation question. Attached to the root and to sheets a write can come from (the profile), reading the session's
/// model from the environment; nothing shows without one.
struct BlocklistSyncQuestions: ViewModifier {
    @Environment(BlocklistSyncModel.self) private var model: BlocklistSyncModel?

    func body(content: Content) -> some View {
        content
            .alert(AlertTitles.blocklistSyncQuestion, isPresented: consentShown) {
                Button("Synchroniser") { Task { await model?.answerConsent(true) } }
                Button("Garder sur cet appareil", role: .cancel) { Task { await model?.answerConsent(false) } }
            } message: {
                Text(BlocklistSyncModel.consentQuestion)
            }
            // The creation question of a first write: « Oui » selected, a « Non » confirmed first (#1014).
            .mpStorageCreationQuestion(model?.mpStorage, prompt: .write)
    }

    private var consentShown: Binding<Bool> {
        Binding(get: { model?.asksConsent ?? false }, set: { if !$0 { model?.asksConsent = false } })
    }
}

extension View {
    /// The blocklist's MPStorage questions (LOT-131).
    func blocklistSyncQuestions() -> some View { modifier(BlocklistSyncQuestions()) }
}
