import Foundation
import HFRModels
import HFRNetwork
@testable import SwiftHFR
import Synchronization
import Testing

/// #1420: HFR answers a profile 403 without `md_id` (`R1420c`, `R1420d`), which the login alone sets, for 30 days (`W1420a`,
/// `R1420g`). Legacy `5c0f10db` tells that refusal apart (`reloginRequired`); SwiftHFR does not even send the request.
/// Every request goes to a double: nothing can reach the forum (LESSONS 56).
struct UserProfileMemberIDTests {
    private static let profileURL = "https://forum.hardware.fr/hfr/profil-910002.htm"

    /// The cookies of an account imported from legacy (LOT-067 keeps legacy's list as is, and legacy's `updateCookies:` had
    /// dropped `md_id`, `5c0f10db`), or of a login past its 30 days: `md_user` and `md_passs` only.
    private static let withoutMemberID = [
        StoredCookie(name: "md_user", value: "user2", domain: ".hardware.fr", expiresDate: .now.addingTimeInterval(86_400)),
        StoredCookie(name: "md_passs", value: "fake-pass", domain: ".hardware.fr", expiresDate: .now.addingTimeInterval(86_400))
    ]
    private static let memberID = StoredCookie(
        name: "md_id", value: "900002", domain: ".hardware.fr", expiresDate: .now.addingTimeInterval(86_400)
    )

    @Test func aSessionWithoutMemberIDAsksToLogInAgainAndSendsNothing() async {
        let session = RecordingProfileSession(loggedIn: true, hasMemberID: false)
        let source = LiveUserProfileSource(session: session)
        await #expect(throws: ListLoadError.profileReloginRequired) { try await source.profile(memberID: 910_002) }
        #expect(await session.transport.requests.isEmpty)
        // A login sets `md_id` (`W1420a`): the request leaves (the scripted transport has no reply: reaching it is the point).
        await session.logIn()
        await #expect(throws: ListLoadError.other) { try await source.profile(memberID: 910_002) }
        #expect(await session.transport.requests.map(\.url.absoluteString) == ["https://forum.hardware.fr/hfr/profil-910002.htm"])
    }

    /// The app's own session: an imported legacy account's jar holds no `md_id`, a fresh login's does. Only the state is read.
    @Test func theAccountSessionReportsItsMemberID() async {
        #expect(await HFRSession(cookies: Self.withoutMemberID).profileLoginState().hasMemberID == false)
        #expect(await HFRSession(cookies: Self.withoutMemberID + [Self.memberID]).profileLoginState().hasMemberID)
        let expired = StoredCookie(name: "md_id", value: "900002", domain: ".hardware.fr", expiresDate: .now.addingTimeInterval(-60))
        #expect(await HFRSession(cookies: Self.withoutMemberID + [expired]).profileLoginState().hasMemberID == false)
    }

    /// HFR's 403 with `md_id` sent stays « accès refusé »; a 403 to a session that lost `md_id` meanwhile (its 30 days ended
    /// during the request) asks to log in again, as legacy's check after the answer (`UserProfileService.swift:43-47` @ 5c0f10db).
    @Test(arguments: [true, false])
    func aRefusalSaysWhetherALoginIsMissing(memberIDAfterTheAnswer: Bool) async {
        let checks = CheckCount()
        let refused = MockTransport { _ async throws(NetworkError) -> HTTPResponse in
            HTTPResponse(statusCode: 403, headers: ["Content-Type": "text/html; charset=iso-8859-1"], url: url(Self.profileURL))
        }
        let source = LiveUserProfileSource(
            fetcher: PageFetcher(session: refused, anonymous: MockTransport(replies: [])), isLoggedIn: { true },
            hasMemberID: {
                // The first check is before the request, the second after HFR's answer.
                checks.next() == 1 || memberIDAfterTheAnswer
            }
        )
        let expected: ListLoadError = memberIDAfterTheAnswer ? .profileAccessDenied : .profileReloginRequired
        await #expect(throws: expected) { try await source.profile(memberID: 910_002) }
        #expect(await refused.requests.count == 1)
    }

    @Test func theReloginStateSaysWhatToDo() {
        let state = ListLoadError.profileReloginRequired
        #expect(state != .profileAccessDenied)
        #expect(state != .profileLoginRequired)
        #expect(state.title == "Connexion requise")
        #expect(state.detail.contains("nouvelle connexion"))
        #expect(state.detail.contains("« Se reconnecter »"))
    }

    /// The avatar lookup (#714) depends on profiles: without `md_id` it is a refusal and nothing leaves, not even the id lookup.
    @Test func anAvatarLookupWithoutMemberIDSendsNothing() async {
        let session = MockTransport(replies: [])
        let anonymous = MockTransport(replies: [])
        let fetcher = PageFetcher(session: session, anonymous: anonymous)
        let lookup = LiveMemberAvatarLookup(
            fetcher: fetcher, profiles: LiveUserProfileSource(fetcher: fetcher, isLoggedIn: { true }, hasMemberID: { false })
        )
        #expect(await lookup.avatar(forPseudo: "user2") == .refused)
        #expect(await session.requests.isEmpty)
        #expect(await anonymous.requests.isEmpty)
    }
}

/// Counts the `md_id` checks of a source.
private final class CheckCount: Sendable {
    private let count = Mutex(0)

    /// The number of this check, from 1.
    func next() -> Int {
        count.withLock { value in
            value += 1
            return value
        }
    }
}
