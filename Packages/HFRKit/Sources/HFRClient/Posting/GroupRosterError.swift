import HFRNetwork

/// Why a group roster change did not end with HFR's confirmation (LOT-058).
///
/// Every case but `posting` means nothing was sent. `posting` is the reply's own outcome, read as `PostingError` says:
/// `rejected` carries HFR's sentence ("Désolé, le pseudo suivant n'existe pas : …", `W76`: nothing was posted, the roster
/// did not move), `unconfirmed` may have changed the roster and is never retried.
public enum GroupRosterError: Error, Sendable, Equatable {
    /// The form is not a private thread's reply composer serving `newdest`: a member who does not own the group (`R123e`),
    /// a one-to-one thread (`R47b`, `R124`). HFR's answer to a `newdest` it did not serve is captured for an unchanged roster
    /// only (`W78`).
    case rosterNotOffered
    /// No name is left. HFR takes an empty `newdest` as "no change" (`W77`), so it cannot mean "remove everyone".
    case emptyRoster
    /// The change would leave fewer than `minimum` other members: from then on the composer serves no `newdest` and nobody
    /// can be added back (`W72`, `R124`).
    case tooFewMembers(minimum: Int)
    /// The list names the owner, whose form lists the others only (`R123c`); HFR's answer to that is not captured.
    case namesOwner
    /// A name holds a comma, the separator of `newdest`, a line break, or a character HFR cuts a text at (`W12`): what HFR
    /// would read is not the roster that was asked for.
    case invalidMemberName
    /// The account session was not confirmed logged in just before the POST (LOT-044 `SessionRefreshFlow`, never `.valid`
    /// here); the POST was not sent.
    case sessionNotConfirmed(SessionHealth)
    /// The reply itself: its text, its form, the session check that could not be done (`network`), or HFR's answer.
    case posting(PostingError)
}
