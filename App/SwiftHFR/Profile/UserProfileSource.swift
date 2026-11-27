import Foundation
import HFRNetwork
import HFRParsing

/// What the profile screen needs from the forum: one member's public profile, fetched and parsed.
protocol UserProfileSource: Sendable {
    /// The public profile of member `memberID` (`/hfr/profil-<id>.htm`, HFR-PROTOCOL R9).
    func profile(memberID: Int) async throws(ListLoadError) -> UserProfile
}

// Port of HFRswift/Swift/UserProfileView.swift (UserProfileService.fetchProfile) @ 2440d79, and of its #1349 fix
// HFRswift/Swift/UserProfileService.swift:23-48 @ bb58131d (master). Differences: the session is the current account's
// `HFRSession` (legacy: the main account's cookies), and a page served at another URL is refused (LOT-116 spec, differences 1
// and 2).
/// The live source: `PageFetcher.profile` (LOT-045) **with the account's session**, then `UserProfileParser` (LOT-027).
///
/// HFR answers a profile request without cookies 403 since 2026-11-26 (`R1363a`) and serves the page to a logged-in session
/// (`R1363b`), so no request leaves without a login (`profileLoginRequired`, legacy `loginRequired`), and a 401 or 403 is
/// `profileAccessDenied` (legacy `accessDenied`), not an unreadable page. A page served at another URL (a redirect the
/// captures do not show, e.g. for a deleted member) is refused rather than read as a profile.
struct LiveUserProfileSource: UserProfileSource {
    let fetcher: PageFetcher
    /// Whether the fetcher's session holds a usable login; checked before every request.
    let isLoggedIn: @Sendable () async -> Bool

    /// A source whose login check is `isLoggedIn` (tests).
    init(fetcher: PageFetcher, isLoggedIn: @escaping @Sendable () async -> Bool) {
        self.fetcher = fetcher
        self.isLoggedIn = isLoggedIn
    }

    /// The source of `session`: its login is checked and its requests leave through it, one value for both.
    init(session: HFRSession) {
        self.init(fetcher: PageFetcher(session: session), isLoggedIn: { await session.isLoggedIn() })
    }

    func profile(memberID: Int) async throws(ListLoadError) -> UserProfile {
        guard await isLoggedIn() else { throw .profileLoginRequired }
        let raw: RawPage
        do throws(NetworkError) {
            raw = try await fetcher.profile(memberID: memberID, as: .authenticated)
        } catch {
            if case .httpStatus(let code, _) = error, code == 401 || code == 403 { throw .profileAccessDenied }
            throw ListLoadError(error)
        }
        guard Self.isProfilePage(raw.finalURL, memberID: memberID) else { throw .unreadable }
        do throws(ParsingError) {
            return try UserProfileParser.parse(html: raw.text)
        } catch {
            throw .unreadable
        }
    }

    /// `https://forum.hardware.fr/hfr/profil-<memberID>.htm`, the only URL a profile is read from (HFR-PROTOCOL R9).
    static func isProfilePage(_ url: URL, memberID: Int) -> Bool {
        url.scheme?.lowercased() == "https" && url.host()?.lowercased() == "forum.hardware.fr" && url.port == nil
            && url.user == nil && url.path(percentEncoded: true) == "/hfr/profil-\(memberID).htm"
    }
}

extension ListLoadError {
    /// No login: no profile request is sent (legacy `UserProfileLoadingError.loginRequired`,
    /// `HFRswift/Swift/UserProfileLoadingError.swift:22-23` @ bb58131d, in the app's « tu »).
    static let profileLoginRequired = ListLoadError.notAuthenticated(
        "Le forum réserve les profils aux membres connectés. Connecte-toi à un compte puis réessaie."
    )
    /// HFR refused the profile although the session was sent, an expired session most likely (legacy `accessDenied`,
    /// `HFRswift/Swift/UserProfileLoadingError.swift:24-26` @ bb58131d).
    static let profileAccessDenied = ListLoadError.notAuthenticated(
        "Le forum a refusé l’accès au profil. Ta session a peut-être expiré : reconnecte-toi puis réessaie."
    )
}
