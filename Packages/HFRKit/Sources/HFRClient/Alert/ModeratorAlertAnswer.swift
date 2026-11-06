/// HFR's confirmation of a submitted alert (`W46`, LOT-037 `.alertSubmit`): the alert reached the moderators.
///
/// Returned only for HFR's own confirmation sentence; every other answer is an error (#395). The app shows `message`,
/// HFR's own sentence (legacy showed any answer as a success, `AlerteModoViewController.m:229-236`).
public struct ModeratorAlertAnswer: Sendable, Equatable {
    /// The `.hop` text of HFR's confirmation, whitespace collapsed, without the back link.
    public let message: String
}
