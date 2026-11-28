import Foundation
import HFRNetwork
import HFRParsing

/// What the profile screen needs from the forum: one member's public profile, fetched and parsed.
protocol UserProfileSource: Sendable {
    /// The public profile of member `memberID` (`/hfr/profil-<id>.htm`, HFR-PROTOCOL R9).
    func profile(memberID: Int) async throws(ListLoadError) -> UserProfile
}

// Port of HFRswift/Swift/UserProfileView.swift (UserProfileService.fetchProfile) @ 2440d79, and of its #1349 fix
// HFRswift/Swift/UserProfileService.swift:23-48 @ bb58131d (master), and of its `md_id` fix UserProfileService.swift:43-47 @
// 5c0f10db (master, #1420). Differences: the session is the current account's `HFRSession` (legacy: the main account's
// cookies), a page served at another URL is refused (LOT-116 spec, differences 1 and 2), and a session without `md_id` sends
// nothing (legacy sends it and reads the 403, which `R1420c` shows is certain).
/// The live source: `PageFetcher.profile` (LOT-045) **with the account's session**, then `UserProfileParser` (LOT-027).
///
/// HFR answers a profile request without cookies 403 since 2026-11-26 (`R1363a`) and serves the page to a logged-in session
/// (`R1363b`), so no request leaves without a login (`profileLoginRequired`, legacy `loginRequired`), and a 401 or 403 is
/// `profileAccessDenied` (legacy `accessDenied`), not an unreadable page. HFR also refuses it without `md_id`, which the login
/// alone sets for 30 days (`R1420c`, `R1420g`): such a session asks to log in again (`profileReloginRequired`, legacy
/// `reloginRequired`, #1420). A page served at another URL (a redirect the captures do not show, e.g. for a deleted member)
/// is refused rather than read as a profile.
struct LiveUserProfileSource: UserProfileSource {
    let fetcher: PageFetcher
    /// The login of the fetcher's session; checked before every request.
    let loginState: @Sendable () async -> ProfileLoginState

    /// A source whose login check is `isLoggedIn` and whose `md_id` check is `hasMemberID` (tests).
    init(
        fetcher: PageFetcher, isLoggedIn: @escaping @Sendable () async -> Bool,
        hasMemberID: @escaping @Sendable () async -> Bool = { true }
    ) {
        self.fetcher = fetcher
        self.loginState = { ProfileLoginState(isLoggedIn: await isLoggedIn(), hasMemberID: await hasMemberID(), generation: 0) }
    }

    /// The source of `session`: its login is checked and its requests leave through it, one value for both.
    init(session: some ProfileSession) {
        self.fetcher = PageFetcher(session: session)
        self.loginState = { await session.profileLoginState() }
    }

    /// Why no profile request may leave now (no login, or no `md_id`); nil when one may.
    func refusal() async -> ListLoadError? {
        let state = await loginState()
        guard state.isLoggedIn else { return .profileLoginRequired }
        return state.hasMemberID ? nil : .profileReloginRequired
    }

    func profile(memberID: Int) async throws(ListLoadError) -> UserProfile {
        if let refusal = await refusal() { throw refusal }
        let raw: RawPage
        do throws(NetworkError) {
            raw = try await fetcher.profile(memberID: memberID, as: .authenticated)
        } catch {
            if case .httpStatus(let code, _) = error, code == 401 || code == 403 {
                // `md_id` may have expired while the request ran: legacy tells the two refusals apart the same way (5c0f10db).
                throw await loginState().hasMemberID ? .profileAccessDenied : .profileReloginRequired
            }
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

/// The login a profile request depends on: whether the session has one, whether it still holds `md_id` (#1420), and which one
/// (`HFRSession.loginGeneration` moves on every login installed, a re-login of the same session included, #1195).
struct ProfileLoginState: Equatable, Sendable {
    let isLoggedIn: Bool
    let hasMemberID: Bool
    let generation: Int
}

/// The session a profile is fetched with: its transport and its login (#1363). `HFRSession` in the app; a recording double in
/// tests, so no test relies on the login check under test to keep a request from the forum (LESSONS 56).
protocol ProfileSession: HTTPTransport {
    /// The session's login now.
    func profileLoginState() async -> ProfileLoginState
}

extension HFRSession: ProfileSession {
    func profileLoginState() -> ProfileLoginState {
        let now = Date()
        return ProfileLoginState(isLoggedIn: isLoggedIn(now: now), hasMemberID: holdsMemberID(now: now), generation: loginGeneration)
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
    /// The session lacks `md_id`, which HFR requires for profiles and sets at login only (legacy `reloginRequired`,
    /// `HFRswift/Swift/UserProfileLoadingError.swift:30-32` @ 5c0f10db, #1420): an account imported from legacy, or a login
    /// past its 30 days. Legacy asks to remove and add the account again; SwiftHFR re-logs it in place (the « Se reconnecter »
    /// action of the account row, `AccountsView`).
    static let profileReloginRequired = ListLoadError.notAuthenticated(
        "Le forum demande désormais une nouvelle connexion pour afficher les profils. "
            + "Dans Comptes, appuie longuement sur ton compte, choisis « Se reconnecter », puis réessaie."
    )
}
