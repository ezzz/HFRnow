import Foundation
import HFRModels
@testable import HFRNetwork
import Testing
@testable import HFRClient

/// LOT-094, #314, #340, #342: the MP thread delete leaves only once LOT-044 confirmed the account session and no login
/// landed in it meanwhile. The checks are scripted closures (or the real `SessionRefreshFlow` with a scripted probe); the
/// delete goes to a scripted session or to a session that may only contact the loopback host. Cookie values are fake.
@Suite("MP thread delete in a confirmed session (LOT-094)")
struct DeletePrivateMessageSessionGateTests {
    static let thread = DeletePrivateMessageFlowTests.thread
    static let token = DeletePrivateMessageFlowTests.token
    private let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))

    @Test(
        "A session the check does not confirm, or a check that fails, sends nothing",
        arguments: [
            Result<SessionHealth, NetworkError>.success(.expired(.noIdentityCookie)),
            .success(.unconfirmed(.unrecognizedPage)), .success(.unconfirmed(.sessionChanged)),
            .failure(.timedOut), .failure(.offline)
        ]
    )
    func unconfirmedSessionSendsNothing(check: Result<SessionHealth, NetworkError>) async throws {
        let session = ScriptedFlagSession([try FlagCapture.page("W64")], hashCheck: Self.token)
        let error = await Self.gated(Self.thread, session) { () async throws(NetworkError) in try check.get() }
        switch check {
        case .success(let health): #expect(error == .sessionNotConfirmed(health))
        case .failure(let failure): #expect(error == .network(failure))
        }
        #expect(await session.requests.isEmpty)
    }

    @Test("In a confirmed session the delete sends the token the session holds after the check (a refresh's fresh one)")
    func confirmedSessionSendsTheFreshToken() async throws {
        let session = ScriptedFlagSession([try FlagCapture.page("W64")], hashCheck: Self.token)
        let result = try await DeletePrivateMessageFlow().delete(Self.thread, through: session) { () async throws(NetworkError) in
            await session.adoptRefreshedToken("fake-token-fresh")
            return .valid
        }
        #expect(result.message == "Action effectuée avec succès")
        let body = try #require(await session.requests.first?.body)
        #expect(String(bytes: body, encoding: .utf8)?.hasPrefix("hash_check=fake-token-fresh&topic0=3207675&") == true)
        #expect(await session.requests.count == 1)
    }

    @Test(
        "A login landing during the check (another account, the same one again, a logout) sends nothing",
        arguments: [
            ConcurrentLogin(identity: "user2", hashCheck: "fake-token-other"),
            ConcurrentLogin(identity: "user1", hashCheck: Self.token),
            ConcurrentLogin(identity: nil, hashCheck: Self.token)
        ]
    )
    func loginDuringTheCheckSendsNothing(login: ConcurrentLogin) async throws {
        let session = ScriptedFlagSession([try FlagCapture.page("W64")], hashCheck: Self.token)
        let error = await Self.gated(Self.thread, session) { () async throws(NetworkError) in
            await session.adoptLogin(login)
            return .valid
        }
        #expect(error == .sessionChanged)
        #expect(await session.requests.isEmpty)
    }

    @Test("A confirmed session without a token sends nothing")
    func missingTokenSendsNothing() async throws {
        let session = ScriptedFlagSession([try FlagCapture.page("W64")])
        #expect(await Self.gated(Self.thread, session) { () async throws(NetworkError) in .valid } == .missingToken)
        #expect(await session.requests.isEmpty)
    }

    @Test("A cancelled task asks nothing and sends nothing")
    func cancelledBeforeTheCheck() async throws {
        let session = ScriptedFlagSession([try FlagCapture.page("W64")], hashCheck: Self.token)
        let task = Task { () async -> (MPThreadDeleteError?, Bool) in
            withUnsafeCurrentTask { $0?.cancel() }
            var checked = false
            let error = await Self.gated(Self.thread, session) { () async throws(NetworkError) in
                checked = true
                return .valid
            }
            return (error, checked)
        }
        let (error, checked) = await task.value
        #expect(error == .network(.cancelled))
        #expect(!checked)
        #expect(await session.requests.isEmpty)
    }

    @Test("The public entry point checks the session first: a session that never logged in sends nothing")
    func publicEntryPointIsGated() async throws {
        // This session may only contact the loopback host: whatever it is asked, nothing can reach HFR.
        let session = HFRSession(
            cookies: [], hashCheck: Self.token, now: now, configuration: .ephemeral, hosts: .exactHost("127.0.0.1")
        )
        await #expect(throws: MPThreadDeleteError.sessionNotConfirmed(.expired(.noIdentityCookie))) {
            try await DeletePrivateMessageFlow().delete(Self.thread, in: session)
        }
    }

    @Test("The public entry point asks HFR: a login form refuses the delete, the profile page lets it leave", arguments: [true, false])
    func publicEntryPointAsksHFR(profilePageServed: Bool) async throws {
        // The account holds its identity cookies, but this session may only contact the loopback host: a delete that
        // leaves is refused before the network. The check's probe is the scripted one passed to `init(refresh:)`.
        let session = HFRSession(
            cookies: [cookie("md_user", "user2"), cookie("md_passs", "pass")], hashCheck: Self.token, now: now,
            configuration: .ephemeral, hosts: .exactHost("127.0.0.1")
        )
        let reply = try Capture.response(profilePageServed ? "R55-p1-profile-edit-page1" : "W00-login-form-anon")
        let factory = ProbeFactory(ScriptedProbe.Step(reply: .success(reply), setCookies: [cookie("md_user", "user2")]))
        let flow = DeletePrivateMessageFlow(refresh: SessionRefreshFlow { cookies, now in factory.make(cookies: cookies, now: now) })
        var error: MPThreadDeleteError?
        do throws(MPThreadDeleteError) {
            _ = try await flow.delete(Self.thread, in: session)
        } catch let caught {
            error = caught
        }
        if profilePageServed {
            // The delete left the gate and was stopped by the loopback-only session.
            guard case .network(.invalidRequest)? = error else {
                Issue.record("expected the delete to be attempted, got \(String(describing: error))")
                return
            }
        } else {
            #expect(error == .sessionNotConfirmed(.unconfirmed(.unrecognizedPage)))
        }
        #expect(factory.probes.count == 1)
        for probe in factory.probes {
            #expect(await probe.requests.map(\.url) == [Capture.profilePage1])
        }
    }

    // MARK: - Helpers

    /// The error the gated delete throws after `check`, nil when it succeeds.
    private static func gated(
        _ thread: TopicID, _ session: ScriptedFlagSession, check: DeletePrivateMessageFlow.SessionCheck
    ) async -> MPThreadDeleteError? {
        do throws(MPThreadDeleteError) {
            _ = try await DeletePrivateMessageFlow().delete(thread, through: session, after: check)
            return nil
        } catch {
            return error
        }
    }

    private func cookie(_ name: String, _ value: String) -> StoredCookie {
        StoredCookie(name: name, value: value, domain: ".hardware.fr", path: "/", expiresDate: now.addingTimeInterval(86_400))
    }
}
