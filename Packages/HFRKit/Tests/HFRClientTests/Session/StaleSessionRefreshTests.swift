import Foundation
import HFRModels
import HFRNetwork
import Testing
@testable import HFRClient

/// #383: `SessionRefreshFlow` on HFR's answer to stale cookies (`R70c`), on the cookie-less answer (`R71b`) and on the
/// doubled `Set-Cookie` of a logged-in answer (`R74` note). Scripted probe, captured pages, fake cookie values.
struct StaleSessionRefreshTests {
    /// A whole second one day ahead: Darwin keeps such an expiry intact (LOT-042 learnings).
    private let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    private var expiry: Date { now.addingTimeInterval(86_400) }
    /// The expiry of `R74`'s `deleted` cookies: `Thu, 01-Jan-1970 00:00:01 GMT`.
    private let epoch = Date(timeIntervalSince1970: 1)

    private func cookie(_ name: String, _ value: String, domain: String = ".hardware.fr", expires: Date? = nil) -> StoredCookie {
        StoredCookie(name: name, value: value, domain: domain, path: "/", expiresDate: expires ?? expiry)
    }

    /// The jar of `R70c`'s meta: the account's `md_user` and `md_id`, a `md_passs` HFR refuses; plus a quote selection.
    private func accountSession() -> HFRSession {
        HFRSession(
            cookies: [
                cookie("md_user", "user2"), cookie("md_passs", "stalepass"), cookie("md_id", "900002"),
                cookie("quoteshardwarefr-13-42", "|7")
            ],
            hashCheck: "oldhash",
            now: now
        )
    }

    private func pairs(_ session: HFRSession) async -> [String] {
        await session.cookies(now: now).map { "\($0.name)=\($0.value)" }
    }

    private func expectUnchanged(_ session: HFRSession) async {
        #expect(await pairs(session) == ["md_id=900002", "md_passs=stalepass", "md_user=user2", "quoteshardwarefr-13-42=|7"])
        #expect(await session.hashCheck == "oldhash")
    }

    private func run(
        _ step: ScriptedProbe.Step, on session: HFRSession
    ) async throws(NetworkError) -> (SessionHealth, ProbeFactory) {
        let factory = ProbeFactory(step)
        let flow = SessionRefreshFlow { cookies, now in factory.make(cookies: cookies, now: now) }
        return (try await flow.refresh(session, now: now), factory)
    }

    private func staleStep() throws -> ScriptedProbe.Step {
        .init(reply: .success(try Capture.response("R70c-profile-edit-page1-stale-session")))
    }

    // MARK: - R70c

    @Test func staleCaptureMetaShapesTheScript() throws {
        let meta = try Capture.meta("R70c")
        #expect(meta.method == "GET")
        #expect(meta.url == Capture.profilePage1.absoluteString)
        #expect(meta.finalURL == Capture.profilePage1.absoluteString)
        #expect(meta.status == 200)
        #expect(meta.setCookieNames.isEmpty)
        #expect(meta.redirects?.isEmpty ?? true)
    }

    @Test func staleSessionPageIsExpiredAndChangesNothing() async throws {
        let session = accountSession()
        let (health, factory) = try await run(try staleStep(), on: session)

        #expect(health == .expired(.credentialsRefused))
        await expectUnchanged(session)
        // One GET of page 1 and nothing else: the refresh target (`unlog.php`) is never followed (`R72a`).
        let probe = try #require(factory.probes.first)
        #expect(factory.probes.count == 1)
        let requests = await probe.requests
        #expect(requests.map(\.url) == [Capture.profilePage1])
        #expect(requests.first?.redirectPolicy == .doNotFollow)
    }

    /// The cookie-less answer ("Mot de passe incorrect !", refresh to `login.php`) proves nothing about these cookies.
    @Test func cookielessProfilePageStaysUnconfirmed() async throws {
        let session = accountSession()
        let step = ScriptedProbe.Step(reply: .success(try Capture.response("R71b-profile-edit-page1-anon")))
        #expect(try await run(step, on: session).0 == .unconfirmed(.unrecognizedPage))
        await expectUnchanged(session)
    }

    /// The stale page is HFR's word only on the request it answered: served elsewhere, redirected or from another
    /// origin, it stays an unrecognized page.
    @Test(arguments: [
        ("https://forum.hardware.fr/", 200),
        ("https://forum.hardware.fr/user/editprofil.php?config=hfr.inc&page=5", 200),
        ("https://forum.hardware.fr.example.com/user/editprofil.php?config=hfr.inc&page=1", 200),
        ("http://forum.hardware.fr/user/editprofil.php?config=hfr.inc&page=1", 200),
        ("https://forum.hardware.fr/user/editprofil.php?config=hfr.inc&page=1", 302)
    ])
    func stalePageElsewhereIsUnconfirmed(url: String, status: Int) async throws {
        let served = try #require(URL(string: url))
        let session = accountSession()
        let step = ScriptedProbe.Step(
            reply: .success(try Capture.response("R70c-profile-edit-page1-stale-session", url: served, status: status))
        )
        #expect(try await run(step, on: session).0 == .unconfirmed(.unrecognizedPage))
        await expectUnchanged(session)
    }

    // MARK: - The session changed while the request ran

    /// A re-login lands while the stale answer is in flight, with a new `md_passs` or, as #340 feared for tokens, the very
    /// cookies the refresh sent: the login generation tells the second one apart.
    @Test(arguments: ["loginpass", "stalepass"])
    func loginAdoptedDuringTheStaleAnswerIsNotReportedExpired(_ password: String) async throws {
        let session = accountSession()
        var step = try staleStep()
        let login = [cookie("md_user", "user2"), cookie("md_passs", password), cookie("md_id", "900002")]
        step.during = { [now] in try? await session.adoptLogin(cookies: login, hashCheck: "newhash", now: now) }

        #expect(try await run(step, on: session).0 == .unconfirmed(.sessionChanged))
        #expect(await pairs(session) == ["md_id=900002", "md_passs=\(password)", "md_user=user2"])
        #expect(await session.hashCheck == "newhash")
    }

    @Test func passwordCookieChangedDuringTheStaleAnswerIsNotReportedExpired() async throws {
        let session = accountSession()
        var step = try staleStep()
        step.during = { [now] in await session.mergeCookies([cookie("md_passs", "freshpass")], now: now) }

        #expect(try await run(step, on: session).0 == .unconfirmed(.sessionChanged))
        #expect(await pairs(session) == ["md_id=900002", "md_passs=freshpass", "md_user=user2", "quoteshardwarefr-13-42=|7"])
    }

    @Test func otherCookiesChangedDuringTheStaleAnswerStillExpire() async throws {
        let session = accountSession()
        var step = try staleStep()
        step.during = { [now] in await session.mergeCookies([cookie("quoteshardwarefr-13-42", "|7|8")], now: now) }

        #expect(try await run(step, on: session).0 == .expired(.credentialsRefused))
    }

    @Test func logoutDuringTheStaleAnswerIsSessionChanged() async throws {
        let session = accountSession()
        var step = try staleStep()
        step.during = { [now] in
            await session.mergeCookies([cookie("md_user", "", expires: now.addingTimeInterval(-1))], now: now)
        }

        #expect(try await run(step, on: session).0 == .unconfirmed(.sessionChanged))
        #expect(await session.userKey(now: now) == nil)
    }

    @Test func cancellationDuringTheStaleAnswerThrows() async throws {
        let session = accountSession()
        var step = try staleStep()
        step.cancelsCaller = true
        let factory = ProbeFactory(step)
        let flow = SessionRefreshFlow { cookies, now in factory.make(cookies: cookies, now: now) }

        // A child task: Swift Testing reports a test that cancels its own task as cancelled (LOT-043 learnings).
        let task = Task { [now] in try await flow.refresh(session, now: now) }
        await #expect(throws: NetworkError.cancelled) { try await task.value }
        await expectUnchanged(session)
    }

    // MARK: - R74: the doubled Set-Cookie of a logged-in answer

    /// Every logged-in answer sets `md_user` and `md_passs` twice: the value for `.hardware.fr`, then `deleted` for
    /// `.forum.hardware.fr`, expired in 1970 (`R74` note). That `deleted` is not a logout: the refresh is `valid` and the
    /// account keeps its identity.
    @Test func doubledSetCookieOfALoggedInAnswerKeepsTheAccountLoggedIn() async throws {
        let meta = try Capture.meta("R74")
        #expect(meta.url == Capture.profilePage1.absoluteString)
        #expect(meta.setCookieNames == ["md_user", "md_user", "md_passs", "md_passs"])

        let session = accountSession()
        let step = ScriptedProbe.Step(
            reply: .success(try Capture.response("R55-p1-profile-edit-page1")),
            setCookies: [
                cookie("md_user", "user2", expires: now.addingTimeInterval(30 * 86_400)),
                cookie("md_user", "deleted", domain: ".forum.hardware.fr", expires: epoch),
                cookie("md_passs", "newpass", expires: now.addingTimeInterval(30 * 86_400)),
                cookie("md_passs", "deleted", domain: ".forum.hardware.fr", expires: epoch)
            ]
        )

        #expect(try await run(step, on: session).0 == .valid)
        #expect(await session.userKey(now: now) == "user2")
        #expect(await pairs(session) == ["md_id=900002", "md_passs=newpass", "md_user=user2", "quoteshardwarefr-13-42=|7"])
        #expect(await session.cookies(now: now).allSatisfy { $0.domain == ".hardware.fr" })
    }
}
