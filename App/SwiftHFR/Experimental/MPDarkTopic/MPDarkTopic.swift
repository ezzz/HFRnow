import HFRStorage

// EXPERIMENTAL(mpDarkTopic, #1014): replaces #859's per-function switches. Legacy has no such switch: the position the other
// HFR+ apps store for a group conversation is read whenever MP storage is on (`MPListView.swift:354-373` @ 87fe0d1c).
/// The words and the migration of the option « MP multiples → dark topic » (Réglages › Expérimental).
enum MPDarkTopic {
    /// The switch's label: the function's own title.
    static let title = "MP multiples → dark topic"

    /// What it does, shown under the switch (no ⓘ, operator 2026-11-17) and read as its hint. Says the switch-off path and what
    /// MP storage adds (the option works without it, #858).
    static let explanation = "Lit les MP multiples comme un sujet : la liste montre la page où vous en étiez (⚑ page / pages), "
        + "garde la conversation non lue tant que vous n'avez pas atteint sa dernière page, et la rouvre à cet endroit. "
        + "La position est gardée dans l'application ; avec Réglages › Stockage MP activé, elle est aussi lue et écrite dans le "
        + "MP de stockage, comme les autres applications HFR+. Désactivé : rien n'est lu ni écrit ; rien n'est supprimé."

    // EXPERIMENTAL(mpDarkTopic, #858): the option is read for the app's own positions too, with MP storage off.
    /// Whether the option is on for the account whose MP storage model is `storage`; off when logged out (no model).
    @MainActor
    static func isOn(for storage: MPStorageSyncModel?) -> Bool {
        guard let storage else { return false }
        return ExperimentalSettings.isOn(.mpDarkTopic, in: storage.experimental)
    }

    /// Whether #859's per-account switch of this function was off in `record`: the member had chosen not to see it, so the
    /// option does not turn it back on for them.
    static func retiredSwitchWasOff(in record: MPStorageSyncRecord?) -> Bool {
        record?.isEnabled(.mpFlags) == false
    }
}
