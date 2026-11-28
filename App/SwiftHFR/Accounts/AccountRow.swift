import Foundation
import HFRModels
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
    /// When the stored login cookies lapse unless the forum renews them (LOT-156); nil when they carry no date.
    var sessionExpiry: Date?
}

extension AccountRow {
    /// The login cookies whose expiry ends the session: `md_user` and `md_passs`, each set for 30 days by the login and again by
    /// the logged-in home page, followed list and profile page (HFR-PROTOCOL §6b, `W03`; doubled `Set-Cookie`, `R74`).
    static let loginCookieNames: Set<String> = [HFRSession.identityCookieName, "md_passs"]

    /// The earliest expiry of the login cookies in `cookies`, ignoring the `deleted` marker; nil when none carries a date.
    static func sessionExpiry(in cookies: [StoredCookie]) -> Date? {
        cookies
            .filter { loginCookieNames.contains($0.name) && $0.value != HFRSession.loggedOutMarker }
            .compactMap(\.expiresDate)
            .min()
    }
}

/// Which account a login is for.
enum LoginTarget: Sendable, Hashable, Identifiable {
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
