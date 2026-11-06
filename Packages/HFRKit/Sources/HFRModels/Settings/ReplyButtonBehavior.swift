/// The `reply_button_behavior` setting: what the reader's reply ("+") button does. Raw values are legacy's
/// (`AppReplyButtonBehavior`, `HFRswift/Swift/Common.swift:243-263` on `master` @21173e7), kept so an import reads them.
public enum ReplyButtonBehavior: String, Sendable, Codable, CaseIterable {
    /// "Réponse rapide" (the default): the composer opens on the topic's draft; selected quotes are merged into it.
    case quick
    /// "Répondre comme le forum": the composer starts from what HFR's answer page serves (the selected quotes), as the
    /// site's own "Répondre" does; the draft is kept and the quotes are merged into it.
    case forum
    /// "Pas d'icône": no reply button.
    case hidden
}
