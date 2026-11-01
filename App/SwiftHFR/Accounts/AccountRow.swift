import HFRNetwork
import UIKit

/// What the app knows about an account's session.
enum AccountSessionStatus: Sendable, Equatable {
    /// Restored from the store; the forum has not confirmed it (yet).
    case restored
    /// Being checked.
    case checking
    /// Confirmed by a login or a session check.
    case valid
    /// No usable identity: the account must log in again.
    case expired
    /// The check could not reach the forum; the session is kept.
    case checkFailed(NetworkError)
}

/// An account as the screens show it: no cookie, no token.
struct AccountRow: Sendable, Equatable, Identifiable {
    /// The account's key (`Account.pseudo`, the `md_user` value).
    let id: String
    /// Name shown in lists and menus.
    let displayName: String
    /// The current account, whose session the app uses.
    let isMain: Bool
    /// Avatar, decoded once by the model.
    let avatar: UIImage?
    /// Session state.
    let status: AccountSessionStatus
}

/// Which account a login is for.
enum LoginTarget: Sendable, Equatable, Identifiable {
    /// A new account, or a known one typed again (it is refreshed in place).
    case newAccount
    /// A known account whose session must be renewed; credentials of another account are refused.
    case existing(id: String, displayName: String)

    /// Identity for sheet presentation.
    var id: String {
        switch self {
        case .newAccount: "new"
        case .existing(let id, _): "existing:\(id)"
        }
    }
}
