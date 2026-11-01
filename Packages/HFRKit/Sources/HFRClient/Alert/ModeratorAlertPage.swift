/// What HFR serves at a message's alert link.
public enum ModeratorAlertPage: Sendable {
    /// HFR says the message was already reported: a `.hop` with a link or an input instead of the form (legacy rule,
    /// `AlerteModoViewController.m:154-160`, LOT-037 `.alertPrepare`). `message` is HFR's own sentence, never a fixed
    /// text; the real page is not captured (#135).
    case alreadyAlerted(message: String?)
    /// The alert form (`R46`), ready for `ModeratorAlertFlow.submit`.
    case form(ModeratorAlertForm)
}
