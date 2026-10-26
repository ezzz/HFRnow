/// The `page` of `/user/editprofil.php` the app reads.
public enum EditProfilePage: Int, Sendable, CaseIterable {
    /// Page 1: read only to refresh the session cookies (`MultisManager.m:281`).
    case cookieRefresh = 1
    /// Page 5: carries `hash_check` and the avatar after a login (`IdentificationViewController.m:246`, `LoginService.swift:87-113`).
    case hashAndAvatar = 5
}
