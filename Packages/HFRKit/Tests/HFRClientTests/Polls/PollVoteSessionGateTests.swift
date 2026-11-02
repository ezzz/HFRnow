import Foundation
import HFRModels
@testable import HFRNetwork
import Testing
@testable import HFRClient

/// LOT-054: the vote leaves only once LOT-044 confirmed the account session, as every flag write (#314).
extension PollVoteFlowTests {
    @Test("A vote in a session the check does not confirm is never sent")
    func unconfirmedSessionSendsNothing() async throws {
        let session = ScriptedFlagSession([try Self.answer("W42")], hashCheck: Self.token)
        let health = SessionHealth.unconfirmed(.unrecognizedPage)
        let poll = try Self.poll("R83-public-own-topic-poll-form-logged-in")
        let result = await Self.result { try await PollVoteFlow().vote(1, in: poll, through: session, after: { health }) }
        #expect(result == .failure(.sessionNotConfirmed(health)))
        #expect(await session.requests.isEmpty)
    }

    @Test("A session check that fails is a network failure, and the vote is not sent")
    func failedCheckSendsNothing() async throws {
        let session = ScriptedFlagSession([try Self.answer("W42")], hashCheck: Self.token)
        let poll = try Self.poll("R83-public-own-topic-poll-form-logged-in")
        let result = await Self.result {
            try await PollVoteFlow().vote(1, in: poll, through: session, after: { () async throws(NetworkError) in
                throw .offline
            })
        }
        #expect(result == .failure(.network(.offline)))
        #expect(await session.requests.isEmpty)
    }

    @Test("An invalid form is refused before the check: nothing is asked of HFR")
    func invalidFormAsksNothing() async throws {
        let session = ScriptedFlagSession([try Self.answer("W42")], hashCheck: Self.token)
        let poll = try Self.poll("R83-public-own-topic-poll-form-logged-in")
        let checks = Counter()
        let result = await Self.result {
            try await PollVoteFlow().vote(5, in: poll, through: session, after: { await checks.increment(); return .valid })
        }
        #expect(result == .failure(.invalidChoice))
        #expect(await checks.value == 0)
        #expect(await session.requests.isEmpty)
    }

    @Test("A cancelled task asks nothing and sends nothing")
    func cancelledBeforeTheCheck() async throws {
        let session = ScriptedFlagSession([try Self.answer("W42")], hashCheck: Self.token)
        let poll = try Self.poll("R83-public-own-topic-poll-form-logged-in")
        let checks = Counter()
        let task = Task { () async -> PollVoteError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do throws(PollVoteError) {
                _ = try await PollVoteFlow().vote(1, in: poll, through: session, after: {
                    await checks.increment()
                    return .valid
                })
                return nil
            } catch {
                return error
            }
        }
        #expect(await task.value == .network(.cancelled))
        #expect(await checks.value == 0)
        #expect(await session.requests.isEmpty)
    }

    @Test("The public entry point checks the session first: a session that never logged in sends no vote")
    func publicEntryPointIsGated() async throws {
        // This session may only contact the loopback host: whatever it is asked, nothing can reach HFR.
        let session = HFRSession(
            cookies: [], hashCheck: Self.token, now: now, configuration: .ephemeral, hosts: .exactHost("127.0.0.1")
        )
        let poll = try Self.poll("R83-public-own-topic-poll-form-logged-in")
        await #expect(throws: PollVoteError.sessionNotConfirmed(.expired(.noIdentityCookie))) {
            try await PollVoteFlow().vote(1, in: poll, session: session)
        }
    }

    @Test("The public entry point asks HFR: a login form refuses the vote, the profile page lets it leave",
          arguments: [true, false])
    func publicEntryPointAsksHFR(profilePageServed: Bool) async throws {
        // The account holds its identity cookies, but this session may only contact the loopback host: a vote that
        // leaves is refused before the network. The check's probe is the scripted one passed to `init(refresh:)`.
        let session = HFRSession(
            cookies: [cookie("md_user", "user2"), cookie("md_passs", "pass")], hashCheck: Self.token, now: now,
            configuration: .ephemeral, hosts: .exactHost("127.0.0.1")
        )
        let reply = try Capture.response(profilePageServed ? "R55-p1-profile-edit-page1" : "W00-login-form-anon")
        let factory = ProbeFactory(ScriptedProbe.Step(reply: .success(reply), setCookies: [cookie("md_user", "user2")]))
        let flow = PollVoteFlow(refresh: SessionRefreshFlow { cookies, now in factory.make(cookies: cookies, now: now) })
        let poll = try Self.poll("R83-public-own-topic-poll-form-logged-in")
        let result = await Self.result { try await flow.vote(1, in: poll, session: session) }
        if profilePageServed {
            // The vote left the gate and was stopped by the loopback-only session.
            guard case .failure(.network(.invalidRequest)) = result else {
                Issue.record("expected the vote to be attempted, got \(result)")
                return
            }
        } else {
            #expect(result == .failure(.sessionNotConfirmed(.unconfirmed(.unrecognizedPage))))
        }
        #expect(factory.probes.count == 1)
        for probe in factory.probes {
            #expect(await probe.requests.map(\.url) == [Capture.profilePage1])
        }
    }
}
