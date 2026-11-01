/// HFR's answer to a submitted alert, as served.
///
/// Neither a success nor a refusal: HFR's answer to `modo.php` is not captured (#136), so the client does not decide
/// what it means. The app shows `message`, HFR's own sentence (legacy showed it as a success, `AlerteModoViewController.m:229-236`).
public struct ModeratorAlertAnswer: Sendable, Equatable {
    /// The `.hop` text of HFR's answer, or its plain-text body (LOT-037), whitespace collapsed.
    public let message: String
}
