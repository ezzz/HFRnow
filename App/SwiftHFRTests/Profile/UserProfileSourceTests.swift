import Foundation
import HFRNetwork
import HFRParsing
@testable import SwiftHFR
import Testing

/// The live source (LOT-116, #1363): HFR answers a profile without cookies 403 (`R1363a`), so the profile goes through the
/// account's session only, never without a login, then LOT-027's parser, on the captured profiles `R1363b` (logged in) and
/// `R56b` (logged out, the same page shape).
struct UserProfileSourceTests {
    private struct Rig {
        let source: LiveUserProfileSource
        let session: MockTransport
        let anonymous: MockTransport
    }

    private static func page(_ body: Data, at address: String, status: Int = 200) -> MockTransport {
        MockTransport { _ async throws(NetworkError) -> HTTPResponse in
            HTTPResponse(statusCode: status, headers: ["Content-Type": "text/html; charset=utf-8"], url: url(address), body: body)
        }
    }

    private func rig(
        _ capture: String, servedAt address: String, status: Int = 200, isLoggedIn: Bool = true
    ) throws -> Rig {
        let body = try LiveTopicPageSourceTests.capture(capture)
        // The cookie-less client answers too, so a source that used it would get the page and pass the parse checks: only the
        // request counts below catch it.
        let session = Self.page(body, at: address, status: status)
        let anonymous = Self.page(body, at: address, status: status)
        let source = LiveUserProfileSource(
            fetcher: PageFetcher(session: session, anonymous: anonymous), isLoggedIn: { isLoggedIn }
        )
        return Rig(source: source, session: session, anonymous: anonymous)
    }

    @Test(arguments: ["R1363b-profile-own-user1.html", "R56b-profile-other-member-anon.html"])
    func theCapturedProfileIsFetchedWithTheSessionAndParsed(capture: String) async throws {
        let rig = try rig(capture, servedAt: "https://forum.hardware.fr/hfr/profil-910002.htm")
        let profile = try await rig.source.profile(memberID: 910_002)
        #expect(await rig.anonymous.requests.isEmpty)
        let requests = await rig.session.requests
        #expect(requests.map(\.url.absoluteString) == ["https://forum.hardware.fr/hfr/profil-910002.htm"])
        let data = try LiveTopicPageSourceTests.capture(capture)
        let html = try #require(String(data: data, encoding: .utf8))
        #expect(profile == (try UserProfileParser.parse(html: html)))
        #expect(profile.avatarURL != nil)
        #expect(!profile.personalSmilies.isEmpty)
    }

    /// Legacy `loginRequired` (`UserProfileService.swift:24-26` @ bb58131d): without a login nothing is sent, on either client.
    @Test func noRequestLeavesWithoutALogin() async throws {
        let rig = try rig(
            "R1363b-profile-own-user1.html", servedAt: "https://forum.hardware.fr/hfr/profil-910002.htm", isLoggedIn: false
        )
        await #expect(throws: ListLoadError.profileLoginRequired) { try await rig.source.profile(memberID: 910_002) }
        #expect(await rig.session.requests.isEmpty)
        #expect(await rig.anonymous.requests.isEmpty)
    }

    /// HFR's 403 page (`R1363a`) and a 401 are their own state (legacy `accessDenied`, `UserProfileService.swift:43-44` @ bb58131d),
    /// not "Erreur du forum" nor an unreadable page; another error status stays a server error.
    @Test(arguments: [401, 403])
    func aRefusalIsAccessDenied(status: Int) async throws {
        let rig = try rig("R1363a-profile-anon-403.html", servedAt: "https://forum.hardware.fr/hfr/profil-910002.htm", status: status)
        await #expect(throws: ListLoadError.profileAccessDenied) { try await rig.source.profile(memberID: 910_002) }
        #expect(await rig.session.requests.count == 1)
    }

    @Test func anotherErrorStatusStaysAServerError() async throws {
        let rig = try rig("R1363a-profile-anon-403.html", servedAt: "https://forum.hardware.fr/hfr/profil-910002.htm", status: 500)
        await #expect(throws: ListLoadError.server(status: 500)) { try await rig.source.profile(memberID: 910_002) }
    }

    @Test func theTwoStatesSayWhatToDo() {
        #expect(ListLoadError.profileLoginRequired != ListLoadError.profileAccessDenied)
        #expect(ListLoadError.profileLoginRequired.title == "Connexion requise")
        #expect(ListLoadError.profileLoginRequired.detail.contains("Connecte-toi"))
        #expect(ListLoadError.profileAccessDenied.detail.contains("reconnecte-toi"))
    }

    /// A page served at another URL (a redirect no capture shows) is not read as a profile, even when it parses as one.
    @Test(arguments: [
        "https://forum.hardware.fr/hfr/profil-910003.htm",
        "https://forum.hardware.fr/",
        "https://evil.example/hfr/profil-910002.htm",
        "http://forum.hardware.fr/hfr/profil-910002.htm",
        "https://forum.hardware.fr:8443/hfr/profil-910002.htm"
    ])
    func aProfileServedElsewhereIsRefused(address: String) async throws {
        let rig = try rig("R1363b-profile-own-user1.html", servedAt: address)
        await #expect(throws: ListLoadError.unreadable) { try await rig.source.profile(memberID: 910_002) }
    }

    /// A page that is not a profile (a topic page) is `unreadable`, never an empty profile.
    @Test func aPageThatIsNotAProfileIsUnreadable() async throws {
        let rig = try rig("R20-topic-p1-anon.html", servedAt: "https://forum.hardware.fr/hfr/profil-910002.htm")
        await #expect(throws: ListLoadError.unreadable) { try await rig.source.profile(memberID: 910_002) }
    }

    @Test func aTransportFailureIsMapped() async {
        let session = MockTransport { _ async throws(NetworkError) -> HTTPResponse in throw .offline }
        let source = LiveUserProfileSource(
            fetcher: PageFetcher(session: session, anonymous: MockTransport(replies: [])), isLoggedIn: { true }
        )
        await #expect(throws: ListLoadError.offline) { try await source.profile(memberID: 1) }
    }

    /// The app's source is built from one session, which it checks and sends with. The session is a recording double that
    /// cannot reach the forum, so the test holds without the login check under test (LESSONS 56).
    @Test func theSessionSourceChecksAndSendsWithItsSession() async {
        let session = RecordingProfileSession(loggedIn: false)
        let source = LiveUserProfileSource(session: session)
        await #expect(throws: ListLoadError.profileLoginRequired) { try await source.profile(memberID: 1) }
        #expect(await session.transport.requests.isEmpty)
        await session.logIn()
        // The scripted transport has no reply: reaching it is the point.
        await #expect(throws: ListLoadError.other) { try await source.profile(memberID: 1) }
        #expect(await session.transport.requests.map(\.url.absoluteString) == ["https://forum.hardware.fr/hfr/profil-1.htm"])
    }

    /// `AppEnvironment` wires the reader's profiles and the MP avatar prefetcher to the environment's own session: both follow
    /// its login generation. Nothing is sent: only the login state is read.
    @Test func theEnvironmentsProfilesFollowItsSession() async throws {
        #expect(AppEnvironment.make(session: HFRSession(), accountName: nil).memberAvatars == nil)
        let name = "ProfileWiringTest"
        let session = HFRSession(cookies: Fake.cookies(user: name))
        let environment = AppEnvironment.make(session: session, accountName: name)
        let source = try #require(environment.reader.profiles as? LiveUserProfileSource)
        let prefetcher = try #require(environment.memberAvatars)
        #expect(await source.loginState() == ProfileLoginState(isLoggedIn: true, generation: 0))
        #expect(await prefetcher.currentLoginState() == ProfileLoginState(isLoggedIn: true, generation: 0))
        await session.advanceLoginGeneration()
        #expect(await source.loginState().generation == 1)
        #expect(await prefetcher.currentLoginState().generation == 1)
    }
}

/// A `ProfileSession` whose transport is a `MockTransport` with no reply: it records requests and never reaches the forum.
actor RecordingProfileSession: ProfileSession {
    let transport = MockTransport(replies: [])
    private var loggedIn: Bool
    private var generation = 0

    init(loggedIn: Bool) { self.loggedIn = loggedIn }

    func logIn() {
        loggedIn = true
        generation += 1
    }

    func profileLoginState() -> ProfileLoginState { ProfileLoginState(isLoggedIn: loggedIn, generation: generation) }

    func perform(_ request: HTTPRequest) async throws(NetworkError) -> HTTPResponse { try await transport.perform(request) }
}
