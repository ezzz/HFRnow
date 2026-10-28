import Foundation
import HFRModels
@testable import HFRNetwork
import Testing
@testable import HFRClient

/// #314: a flag write leaves only once LOT-044 confirmed the account session. HFR answers an `addflag` sent without any
/// cookie with the bytes of the logged-in success (`P03q` = `P03a`), so the sentence alone never proves the write.
/// The check is the real `SessionRefreshFlow`, its probe answered by captures (`R55-p1` logged in; `W00` standing in for
/// the uncaptured stale-cookie answer, as in `SessionRefreshFlowTests`); the write goes to a scripted session.
/// Cookie values are fake.
@Suite("Flag writes in a confirmed session (#314)")
struct FlagSessionGateTests {
    static let cuisine = TopicID(category: .forum(13), topic: 28563)
    static let token = "fake-token-0123"
    private let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))

    /// A session the check does not confirm, with the health it reports.
    enum Unconfirmed: CaseIterable, Sendable {
        /// No `md_user` in the jar: the check sends nothing.
        case neverLoggedIn
        /// `md_user` is set, but HFR answers the profile page with its login form (`W00`).
        case loginFormServed

        var health: SessionHealth {
            switch self {
            case .neverLoggedIn: .expired(.noIdentityCookie)
            case .loginFormServed: .unconfirmed(.unrecognizedPage)
            }
        }
    }

    /// What one gated write did.
    struct Run {
        var result: Result<TopicFlagResult, TopicFlagError>
        /// Requests of the write itself.
        var writes: [HTTPRequest]
        /// Requests of the session check.
        var checks: [HTTPRequest]
    }

    // MARK: - Why

    @Test("P03q, an addflag without cookies, is byte for byte the logged-in success P03a, which the bare write accepts")
    func loggedOutAnswerIsTheSuccessPage() async throws {
        #expect(try Capture.page("P03q-addflag-logged-out") == Capture.page("P03a-addflag-success"))
        #expect(try FlagCapture.requestURL("P03q") == FlagCapture.requestURL("P03a"))
        let session = ScriptedFlagSession([try FlagCapture.page("P03q")])
        let ungated = try await TopicFlagFlow().follow(.addFavorite, link: try FlagCapture.requestURL("P03q"), through: session)
        #expect(ungated.message == "Favori positionné avec succès")
    }

    // MARK: - Gate

    @Test(
        "A write in a session the check does not confirm is never sent, so never a success (addflag answered P03q)",
        arguments: TopicFlagAction.allCases, Unconfirmed.allCases
    )
    func unconfirmedSessionSendsNothing(action: TopicFlagAction, state: Unconfirmed) async throws {
        let answer = ["P03q", "P03n", "P03j"][TopicFlagAction.allCases.firstIndex(of: action) ?? 0]
        let run = try await run(
            action, answer: answer, loggedIn: state == .loginFormServed,
            probeReply: .success(try Capture.response("W00-login-form-anon"))
        )
        #expect(run.result == .failure(.sessionNotConfirmed(state.health)))
        #expect(run.writes.isEmpty)
        #expect(run.checks.count == (state == .neverLoggedIn ? 0 : 1))
    }

    @Test(
        "In a confirmed session the write follows one GET of the profile page and is confirmed by its sentence",
        arguments: TopicFlagAction.allCases
    )
    func confirmedSessionWrites(action: TopicFlagAction) async throws {
        let answer = ["P03a", "P03n", "P03j"][TopicFlagAction.allCases.firstIndex(of: action) ?? 0]
        let run = try await run(
            action, answer: answer, loggedIn: true,
            probeReply: .success(try Capture.response("R55-p1-profile-edit-page1"))
        )
        let result = try run.result.get()
        #expect(result.action == action)
        #expect(result.topic == Self.cuisine)
        #expect(action.confirmations.contains(result.message))
        #expect(run.checks.map(\.url) == [Capture.profilePage1])
        #expect(run.checks.first?.method == .get)
        #expect(run.writes.count == 1)
    }

    @Test("The public entry points check the session first: a session that never logged in sends no write")
    func publicEntryPointsAreGated() async throws {
        // This session may only contact the loopback host: whatever it is asked, nothing can reach HFR.
        let session = HFRSession(
            cookies: [], hashCheck: Self.token, now: now, configuration: .ephemeral, hosts: .exactHost("127.0.0.1")
        )
        let expected = TopicFlagError.sessionNotConfirmed(.expired(.noIdentityCookie))
        let flow = TopicFlagFlow()
        await #expect(throws: expected) { try await flow.addFavorite(link: try FlagCapture.requestURL("P03a"), in: session) }
        await #expect(throws: expected) { try await flow.removeFlag(link: try FlagCapture.requestURL("P03n"), in: session) }
        await #expect(throws: expected) { try await flow.removeFavoriteFromList(Self.cuisine, in: session) }
    }

    @Test(
        "A session check that fails is a network failure, and the write is not sent",
        arguments: [NetworkError.timedOut, .offline, .httpStatus(code: 503, url: Capture.profilePage1)]
    )
    func failedCheckSendsNothing(failure: NetworkError) async throws {
        let run = try await run(.addFavorite, answer: "P03a", loggedIn: true, probeReply: .failure(failure))
        #expect(run.result == .failure(.network(failure)))
        #expect(run.writes.isEmpty)
        #expect(run.checks.count == 1)
    }

    @Test("An invalid link or topic is refused before the check: nothing is asked of HFR")
    func invalidInputAsksNothing() async throws {
        let foreign = try FlagCapture.url("https://evil.example/user/addflag.php?config=hfr.inc&cat=13&post=28563")
        let (check, factory) = check(loggedIn: true, reply: .success(try Capture.response("R55-p1-profile-edit-page1")))
        let session = ScriptedFlagSession([try FlagCapture.page("P03a")], hashCheck: Self.token)
        await #expect(throws: TopicFlagError.invalidLink) {
            try await TopicFlagFlow().follow(.addFavorite, link: foreign, through: session, after: check)
        }
        await #expect(throws: TopicFlagError.invalidTopic) {
            try await TopicFlagFlow().removeFavoriteFromList(
                TopicID(category: .privateMessages, topic: 5), through: session, after: check
            )
        }
        #expect(factory.probes.isEmpty)
        #expect(await session.requests.isEmpty)
    }

    @Test("A cancelled task asks nothing and sends nothing")
    func cancelledBeforeTheCheck() async throws {
        let link = try FlagCapture.requestURL("P03a")
        let (check, factory) = check(loggedIn: true, reply: .success(try Capture.response("R55-p1-profile-edit-page1")))
        let session = ScriptedFlagSession([try FlagCapture.page("P03a")])
        let task = Task { () async -> TopicFlagError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do throws(TopicFlagError) {
                _ = try await TopicFlagFlow().follow(.addFavorite, link: link, through: session, after: check)
                return nil
            } catch {
                return error
            }
        }
        #expect(await task.value == .network(.cancelled))
        #expect(factory.probes.isEmpty)
        #expect(await session.requests.isEmpty)
    }

    // MARK: - Helpers

    private func cookie(_ name: String, _ value: String) -> StoredCookie {
        StoredCookie(name: name, value: value, domain: ".hardware.fr", path: "/", expiresDate: now.addingTimeInterval(86_400))
    }

    /// A check by the real refresh flow on an account session, its probe answered `reply` (which sets `md_user` again,
    /// as `R55-p1` does); the factory keeps the probes.
    private func check(
        loggedIn: Bool, reply: Result<HTTPResponse, NetworkError>
    ) -> (TopicFlagFlow.SessionCheck, ProbeFactory) {
        let identity = [cookie("md_user", "user2"), cookie("md_passs", "pass")]
        let account = HFRSession(cookies: loggedIn ? identity : [], now: now)
        let factory = ProbeFactory(ScriptedProbe.Step(reply: reply, setCookies: [cookie("md_user", "user2")]))
        let flow = SessionRefreshFlow { cookies, now in factory.make(cookies: cookies, now: now) }
        let now = now
        return ({ () async throws(NetworkError) -> SessionHealth in try await flow.refresh(account, now: now) }, factory)
    }

    /// Runs `action` through the gate on the topic of `P03a` and `P03n`, the write answered by the capture `answer`.
    private func run(
        _ action: TopicFlagAction, answer: String, loggedIn: Bool, probeReply: Result<HTTPResponse, NetworkError>
    ) async throws -> Run {
        let (check, factory) = check(loggedIn: loggedIn, reply: probeReply)
        let session = ScriptedFlagSession([try FlagCapture.page(answer)], hashCheck: Self.token)
        let flow = TopicFlagFlow()
        let link = try FlagCapture.requestURL(action == .removeFlag ? "P03n" : "P03a")
        let result: Result<TopicFlagResult, TopicFlagError>
        do throws(TopicFlagError) {
            if action == .removeFavoriteFromList {
                result = .success(try await flow.removeFavoriteFromList(Self.cuisine, through: session, after: check))
            } else {
                result = .success(try await flow.follow(action, link: link, through: session, after: check))
            }
        } catch {
            result = .failure(error)
        }
        var checks: [HTTPRequest] = []
        for probe in factory.probes {
            checks += await probe.requests
        }
        return Run(result: result, writes: await session.requests, checks: checks)
    }
}
