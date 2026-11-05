import Foundation
import HFRModels
import HFRParsing

/// HFR's moderator alert form for one message, read through the account's session; it can only be submitted through
/// that session (decision Q-8). It also keeps the identity the session had when the page was requested, so a form read
/// before a logout or a login of another account in that same session is refused locally (`sessionChanged`, as
/// `PostingForm` does since issue #342).
public struct ModeratorAlertForm: Sendable {
    /// The form as served (`R46`: `hash_check`, `referer_page`, `Submit`; the `raison` textarea is the user's text).
    public let form: ForumForm
    /// The message reported; the link and the form's action both name it.
    public let target: ModeratorAlertTarget
    /// Where the form is posted: its action, an `https` forum page with the alert path.
    public let submitURL: URL
    let layout: HopFormLayout
    let session: any PostingSession
    /// The session's identity and token as the alert page request left (`ModeratorAlertFlow.prepare`).
    let seed: HashCheckSeed
}
