import Foundation

extension StoredCookie {
    /// Name of HFR's member-id cookie. The login alone sets it, for 30 days (`W03`, `W1420a`, `W1420b`): later pages refresh
    /// `md_user` and `md_passs`, never it (`R1420g`). HFR answers a profile 403 without it (`R1420c`, #1420).
    public static let memberIDName = "md_id"

    /// True for an `md_id` a profile request can send at `now`: not empty, not HFR's `deleted` logout marker (`R283b`), not
    /// expired. The one rule of the session, the account sync and the iCloud adoption (#1420).
    public func isLiveMemberID(at now: Date) -> Bool {
        name == Self.memberIDName && !value.isEmpty && value != "deleted" && (expiresDate.map { $0 > now } ?? true)
    }
}
