import Foundation
import HFRModels
import HFRParsing
@testable import HFRNetwork
import Testing
@testable import HFRClient

/// LOT-058, the public entry point: the session is the real `HFRSession`, which may only contact the loopback host, so
/// whatever the flow does nothing can reach HFR (#314, LESSONS 56). Cookie values are fake.
@Suite("Group roster changes: public entry point")
struct GroupRosterSessionTests {
    private let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))

    private func session(loggedIn: Bool) -> HFRSession {
        let cookies = loggedIn ? [cookie("md_user", "user1"), cookie("md_passs", "pass")] : []
        return HFRSession(cookies: cookies, hashCheck: "fake-token", now: now, configuration: .ephemeral, hosts: .exactHost("127.0.0.1"))
    }

    private func cookie(_ name: String, _ value: String) -> StoredCookie {
        StoredCookie(name: name, value: value, domain: ".hardware.fr", path: "/", expiresDate: now.addingTimeInterval(86_400))
    }

    /// The captured owner's composer as if `session` had loaded it.
    private func form(in session: HFRSession) async throws -> PostingForm {
        let html = try Capture.page(try #require(PostingCapture.forms["R127"]))
        return PostingForm(
            form: try HopFormParser.parse(html), layout: try HopFormParser.layout(html),
            pageURL: try PostingCapture.pageURL("R127"), session: session, seed: await session.hashCheckSeed()
        )
    }

    private static func failure(_ body: () async throws(GroupRosterError) -> GroupRosterChange) async -> GroupRosterError? {
        do throws(GroupRosterError) {
            _ = try await body()
            return nil
        } catch {
            return error
        }
    }

    @Test("A session that never logged in sends nothing: the check needs no request")
    func neverLoggedIn() async throws {
        let session = session(loggedIn: false)
        let form = try await form(in: session)
        let error = await Self.failure { () async throws(GroupRosterError) in
            try await GroupRosterFlow().changeMembers(to: ["user3", "user4"], text: "text", with: form, in: session)
        }
        #expect(error == .sessionNotConfirmed(.expired(.noIdentityCookie)))
    }

    @Test("A form loaded through another session is refused before the check")
    func otherSession() async throws {
        let form = try await form(in: session(loggedIn: true))
        let factory = ProbeFactory(ScriptedProbe.Step(reply: .failure(.offline), setCookies: []))
        let flow = GroupRosterFlow(refresh: SessionRefreshFlow { cookies, now in factory.make(cookies: cookies, now: now) })
        let other = session(loggedIn: true)
        let error = await Self.failure { () async throws(GroupRosterError) in
            try await flow.changeMembers(to: ["user3", "user4"], text: "text", with: form, in: other)
        }
        #expect(error == .posting(.sessionChanged))
        #expect(factory.probes.isEmpty)
    }

    @Test("The entry point asks HFR first: a login form stops the write, the profile page lets it leave", arguments: [true, false])
    func asksHFR(profilePageServed: Bool) async throws {
        let session = session(loggedIn: true)
        let form = try await form(in: session)
        let reply = try Capture.response(profilePageServed ? "R55-p1-profile-edit-page1" : "W00-login-form-anon")
        let factory = ProbeFactory(ScriptedProbe.Step(reply: .success(reply), setCookies: [cookie("md_user", "user1")]))
        let flow = GroupRosterFlow(refresh: SessionRefreshFlow { cookies, now in factory.make(cookies: cookies, now: now) })
        let error = await Self.failure { () async throws(GroupRosterError) in
            try await flow.changeMembers(to: ["user3", "user4"], text: "text", with: form, in: session)
        }
        if profilePageServed {
            // The write left the gate and was stopped by the loopback-only session.
            guard case .posting(.network(.invalidRequest))? = error else {
                Issue.record("expected the write to be attempted, got \(String(describing: error))")
                return
            }
        } else {
            #expect(error == .sessionNotConfirmed(.unconfirmed(.unrecognizedPage)))
        }
        #expect(factory.probes.count == 1)
    }
}
