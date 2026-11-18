import HFRStorage

// EXPERIMENTAL(mpDarkTopic, #1014): replaces #859's per-function switches. Legacy has no such switch: the position the other
// HFR+ apps store for a group conversation is read whenever MP storage is on (`MPListView.swift:354-373` @ 87fe0d1c).
/// The words and the migration of the option « MP multiples → dark topic » (Réglages › Expérimental).
enum MPDarkTopic {
    /// The switch's label: the function's own title.
    static let title = "MP multiples → dark topic"

    /// What it does, shown under the ⓘ (#1128, replacing the under-the-switch choice of 2026-11-17) and read as its hint. Says the switch-off path and that
    /// the option needs MP storage.
    static let explanation = "Affiche dans la liste des MP multiples la page où vous en étiez, enregistrée par les autres applications "
        + "HFR+ dans le MP de stockage (Réglages › Stockage MP doit être activé). Cette application ne l'écrit pas encore. "
        + "Désactivé : ces positions ne sont pas lues ; rien n'est supprimé du MP de stockage."

    /// Whether #859's per-account switch of this function was off in `record`: the member had chosen not to see it, so the
    /// option does not turn it back on for them.
    static func retiredSwitchWasOff(in record: MPStorageSyncRecord?) -> Bool {
        record?.isEnabled(.mpFlags) == false
    }
}
