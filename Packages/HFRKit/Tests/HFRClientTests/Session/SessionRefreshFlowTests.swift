import Foundation
import HFRModels
import HFRNetwork
import Testing
@testable import HFRClient

/// Drives `SessionRefreshFlow.refresh` on the captured profile page 1 (`R55-p1`) and on logged-out pages standing in
/// for the uncaptured stale-cookie answer, with a scripted probe instead of the network. Cookie values are fake.
struct SessionRefreshFlowTests {
    /// A whole second one day ahead: Darwin keeps such an expiry intact (LOT-042 learnings).
    private let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    private var expiry: Date { now.addingTimeInterval(86_400) }

    private func forumCookie(_ name: String, _ value: String, expires: Date? = nil) -> StoredCookie {
        StoredCookie(name: name, value: value, domain: ".hardware.fr", path: "/", expiresDate: expires ?? expiry)
    }

    /// The account session before the refresh (names of `W03`'s login cookies plus a multi-quote selection).
    private func accountSession() -> HFRSession {
        HFRSession(
            cookies: [
                forumCookie("md_user", "user2"), forumCookie("md_passs", "oldpass"), forumCookie("md_id", "900002"),
                forumCookie("quoteshardwarefr-13-42", "|7")
            ],
            hashCheck: "oldhash",
            now: now
        )
    }

    private func pairs(_ session: HFRSession) async -> [String] {
        await session.cookies(now: now).map { "\($0.name)=\($0.value)" }
    }

    private func expectUnchanged(_ session: HFRSession) async {
        #expect(await pairs(session) == ["md_id=900002", "md_passs=oldpass", "md_user=user2", "quoteshardwarefr-13-42=|7"])
        #expect(await session.hashCheck == "oldhash")
    }

    private func run(
        _ step: ScriptedProbe.Step, on session: HFRSession
    ) async throws(NetworkError) -> (SessionHealth, ProbeFactory) {
        let factory = ProbeFactory(step)
        let flow = SessionRefreshFlow { cookies, now in factory.make(cookies: cookies, now: now) }
        return (try await flow.refresh(session, now: now), factory)
    }

    /// `R55-p1` with the cookies its meta says it sets (`md_user` again, a new `md_passs`).
    private func validStep() throws -> ScriptedProbe.Step {
        .init(
            reply: .success(try Capture.response("R55-p1-profile-edit-page1")),
            setCookies: [forumCookie("md_user", "user2"), forumCookie("md_passs", "newpass")]
        )
    }

    // MARK: - Valid

    @Test func captureMetaShapesTheScript() throws {
        let meta = try Capture.meta("R55-p1")
        #expect(meta.method == "GET")
        #expect(meta.url == Capture.profilePage1.absoluteString)
        #expect(meta.status == 200)
        #expect(Set(meta.setCookieNames) == ["md_user", "md_passs"])
    }

    @Test func validRefreshMergesWhatHFRSetAndTheToken() async throws {
        let session = accountSession()
        let (health, factory) = try await run(try validStep(), on: session)

        #expect(health == .valid)
        // Merge, not replace (legacy `updateCookies` kept only the answer's cookies): md_id and the selection stay.
        #expect(await pairs(session) == ["md_id=900002", "md_passs=newpass", "md_user=user2", "quoteshardwarefr-13-42=|7"])
        #expect(await session.hashCheck == "REDACTED") // the anonymized token of R55-p1

        let probe = try #require(factory.probes.first)
        #expect(factory.probes.count == 1)
        let requests = await probe.requests
        #expect(requests.count == 1)
        #expect(requests.first?.method == .get)
        #expect(requests.first?.url == Capture.profilePage1)
        #expect(requests.first?.redirectPolicy == .doNotFollow)
    }

    @Test func probeStartsFromTheSessionCookies() async throws {
        let session = accountSession()
        let before = await session.cookies(now: now)
        let (_, factory) = try await run(.init(reply: .success(try Capture.response("W00-login-form-anon"))), on: session)
        #expect(await factory.probes.first?.seed == before)
    }

    @Test func cookieRemovedByHFRIsRemovedOnAValidRefresh() async throws {
        var step = try validStep()
        step.setCookies.append(forumCookie("quoteshardwarefr-13-42", "", expires: now.addingTimeInterval(-60)))
        let session = accountSession()

        #expect(try await run(step, on: session).0 == .valid)
        #expect(await pairs(session) == ["md_id=900002", "md_passs=newpass", "md_user=user2"])
    }

    @Test func concurrentChangesWinOverTheProbeCopy() async throws {
        let session = accountSession()
        var step = try validStep()
        step.during = { [now, expiry] in
            await session.mergeCookies([StoredCookie(name: "md_passs", value: "concurrent", domain: ".hardware.fr",
                                                     expiresDate: expiry)], now: now)
            await session.updateHashCheck("concurrenthash")
        }

        #expect(try await run(step, on: session).0 == .valid)
        #expect(await pairs(session) == ["md_id=900002", "md_passs=concurrent", "md_user=user2", "quoteshardwarefr-13-42=|7"])
        #expect(await session.hashCheck == "concurrenthash")
    }

    // MARK: - Expired: nothing sent

    @Test(arguments: ["none", "expired", "deleted"])
    func noUsableIdentityIsExpiredWithoutSending(_ identity: String) async throws {
        var cookies = [forumCookie("md_passs", "oldpass")]
        switch identity {
        case "expired": cookies.append(forumCookie("md_user", "user2", expires: now.addingTimeInterval(-1)))
        case "deleted": cookies.append(forumCookie("md_user", "deleted"))
        default: break
        }
        let session = HFRSession(cookies: cookies, hashCheck: "oldhash", now: now)
        let before = await session.cookies(now: now)

        let (health, factory) = try await run(try validStep(), on: session)

        #expect(health == .expired(.noIdentityCookie))
        #expect(factory.probes.isEmpty)
        #expect(await session.cookies(now: now) == before)
        #expect(await session.hashCheck == "oldhash")
    }

    // MARK: - Unconfirmed: the session is left alone

    /// Logged-out GET pages (empty or absent token, `.hop` notice) standing in for the uncaptured stale-cookie answer,
    /// plus a POST answer that echoes a token inside a `.hop` (`W17c`). None is offered as a captured page-1 state.
    @Test(arguments: [
        "W00-login-form-anon", "R01-home-anon", "R40b-reply-form-anon", "R12-favourites-anon",
        "W17c-mp-reply-logged-out-rejected"
    ])
    func pagesWithoutTheAccountTokenAreUnconfirmed(_ file: String) async throws {
        let session = accountSession()
        let step = ScriptedProbe.Step(
            reply: .success(try Capture.response(file)),
            setCookies: [forumCookie("md_passs", "newpass")]
        )
        #expect(try await run(step, on: session).0 == .unconfirmed(.unrecognizedPage))
        await expectUnchanged(session)
    }

    @Test func profilePageServedElsewhereOrRedirectedIsUnconfirmed() async throws {
        let home = URL(string: "https://forum.hardware.fr/") ?? Capture.profilePage1
        let page5 = URL(string: "https://forum.hardware.fr/user/editprofil.php?config=hfr.inc&page=5") ?? Capture.profilePage1
        for reply in [
            try Capture.response("R55-p1-profile-edit-page1", url: home),
            // A redirect followed anyway (by a transport ignoring the policy) to another page of the same path.
            try Capture.response("R55-p5-profile-edit-page5", url: page5),
            try Capture.response("R55-p1-profile-edit-page1", status: 302)
        ] {
            let session = accountSession()
            #expect(try await run(.init(reply: .success(reply)), on: session).0 == .unconfirmed(.unrecognizedPage))
            await expectUnchanged(session)
        }
    }

    /// The profile page answered from another origin (a probe reached elsewhere) proves nothing about the forum session.
    @Test(arguments: [
        "https://forum.hardware.fr.example.com/user/editprofil.php?config=hfr.inc&page=1",
        "https://example.com/user/editprofil.php?config=hfr.inc&page=1",
        "http://forum.hardware.fr/user/editprofil.php?config=hfr.inc&page=1",
        "https://forum.hardware.fr:8443/user/editprofil.php?config=hfr.inc&page=1"
    ])
    func profilePageFromAnotherOriginIsUnconfirmed(_ origin: String) async throws {
        let url = try #require(URL(string: origin))
        let session = accountSession()
        let step = ScriptedProbe.Step(
            reply: .success(try Capture.response("R55-p1-profile-edit-page1", url: url)),
            setCookies: [forumCookie("md_user", "user2"), forumCookie("md_passs", "newpass")]
        )
        #expect(try await run(step, on: session).0 == .unconfirmed(.unrecognizedPage))
        await expectUnchanged(session)
    }

    @Test(arguments: ["deleted", "user1", "removed"])
    func identityNotKeptByTheAnswerIsUnconfirmed(_ answer: String) async throws {
        var step = try validStep()
        step.setCookies = answer == "removed"
            ? [forumCookie("md_user", "", expires: now.addingTimeInterval(-60))]
            : [forumCookie("md_user", answer), forumCookie("md_passs", "newpass")]
        let session = accountSession()

        #expect(try await run(step, on: session).0 == .unconfirmed(.identityNotConfirmed))
        await expectUnchanged(session)
    }

    @Test func sessionLoggedOutDuringTheRefreshIsNotRevived() async throws {
        let session = accountSession()
        var step = try validStep()
        step.during = { [now] in
            await session.mergeCookies([StoredCookie(name: "md_user", value: "", domain: ".hardware.fr",
                                                     expiresDate: now.addingTimeInterval(-1))], now: now)
        }

        #expect(try await run(step, on: session).0 == .unconfirmed(.sessionChanged))
        #expect(await session.userKey(now: now) == nil)
        #expect(await pairs(session) == ["md_id=900002", "md_passs=oldpass", "quoteshardwarefr-13-42=|7"])
        #expect(await session.hashCheck == "oldhash")
    }

    // MARK: - Errors

    @Test(arguments: [NetworkError.timedOut, .offline, .httpStatus(code: 500, url: Capture.profilePage1)])
    func transportFailuresThrowAndChangeNothing(_ failure: NetworkError) async throws {
        let session = accountSession()
        let reply: Result<HTTPResponse, NetworkError> = switch failure {
        case .httpStatus: .success(try Capture.response("R55-p1-profile-edit-page1", status: 500))
        default: .failure(failure)
        }
        let step = ScriptedProbe.Step(reply: reply, setCookies: [forumCookie("md_passs", "newpass")])

        await #expect(throws: failure) { try await run(step, on: session) }
        await expectUnchanged(session)
    }

    @Test func cancellationChangesNothing() async throws {
        let session = accountSession()
        var step = try validStep()
        step.cancelsCaller = true
        let factory = ProbeFactory(step)
        let flow = SessionRefreshFlow { cookies, now in factory.make(cookies: cookies, now: now) }

        // A child task: Swift Testing reports a test that cancels its own task as cancelled (LOT-043 learnings).
        let task = Task { [now] in try await flow.refresh(session, now: now) }
        await #expect(throws: NetworkError.cancelled) { try await task.value }
        await expectUnchanged(session)
    }
}
