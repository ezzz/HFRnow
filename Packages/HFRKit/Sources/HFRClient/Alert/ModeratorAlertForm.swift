import Foundation
import HFRModels
import HFRParsing

/// HFR's moderator alert form for one message, read through the account's session; it can only be submitted through
/// that session (decision Q-8).
public struct ModeratorAlertForm: Sendable {
    /// The form as served (`R46`: `hash_check`, `referer_page`, `Submit`; the `raison` textarea is the user's text).
    public let form: ForumForm
    /// The message reported; the link and the form's action both name it.
    public let target: ModeratorAlertTarget
    /// Where the form is posted: its action, an `https` forum page with the alert path.
    public let submitURL: URL
    let layout: HopFormLayout
    let session: any PostingSession
}
