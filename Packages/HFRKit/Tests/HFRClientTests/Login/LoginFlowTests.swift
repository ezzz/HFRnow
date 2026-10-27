import Foundation
import HFRModels
import HFRNetwork
import Testing
@testable import HFRClient

/// Drives `LoginFlow.login` on the captured login answers (`W01`, `W01b`, `W03`) and profile pages (`R55-p5`,
/// `R55-p5u1`), with a scripted jar standing in for the network. Cookie values are fake.
struct LoginFlowTests {
    private static let loginURL = URL(string: "https://forum.hardware.fr/login_validation.php?config=hfr.inc")
        ?? URL(fileURLWithPath: "/")
    private static let profileURL = URL(string: "https://forum.hardware.fr/user/editprofil.php?config=hfr.inc&page=5")
        ?? URL(fileURLWithPath: "/")

    /// A whole second one day ahead: Darwin keeps such an expiry intact (LOT-042 learnings).
    private let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    private var expiry: Date { now.addingTimeInterval(86_400) }

    private func forumCookie(_ name: String, _ value: String) -> StoredCookie {
        StoredCookie(name: name, value: value, domain: ".hardware.fr", path: "/", expiresDate: expiry)
    }

    /// The cookies `W03` sets (names from its meta, fake values).
    private func loginCookies(user: String) -> [StoredCookie] {
        [forumCookie("md_user", user), forumCookie("md_passs", "fakepass"), forumCookie("md_id", "900002")]
    }

    /// The account session before the login: another identity, a multi-quote selection and an old token.
    private func targetSession() -> HFRSession {
        HFRSession(
            cookies: [forumCookie("md_user", "olduser"), forumCookie("md_passs", "oldpass"), forumCookie("quoteshardwarefr-13-42", "|7")],
            hashCheck: "oldhash",
            now: now
        )
    }

    private func page(_ file: String, at url: URL) throws -> Result<HTTPResponse, NetworkError> {
        .success(try Capture.response(file, url: url))
    }

    private func successSteps(user: String = "user2", profile: String = "R55-p5-profile-edit-page5") throws -> [ScriptedLoginJar.Step] {
        [
            .init(reply: try page("W03-login-success", at: Self.loginURL), setCookies: loginCookies(user: user)),
            .init(reply: try page(profile, at: Self.profileURL), setCookies: [forumCookie("md_passs", "refreshedpass")])
        ]
    }

    private func flow(_ jar: ScriptedLoginJar) -> (LoginFlow, JarFactory) {
        let factory = JarFactory(jar)
        return (LoginFlow(makeJar: { factory.make() }), factory)
    }

    /// Asserts the session still holds what `targetSession()` gave it.
    private func expectUnchanged(_ session: HFRSession) async {
        let names = await session.cookies(now: now).map { "\($0.name)=\($0.value)" }
        #expect(names == ["md_passs=oldpass", "md_user=olduser", "quoteshardwarefr-13-42=|7"])
        #expect(await session.hashCheck == "oldhash")
    }

    // MARK: - Success

    @Test func successReplacesCookiesAndTokenOnlyAfterTheProfilePage() async throws {
        let jar = ScriptedLoginJar(try successSteps())
        let (flow, _) = flow(jar)
        let session = targetSession()

        let result = try await flow.login(pseudo: "  user2 ", password: "fake password", into: session, now: now)

        #expect(result == LoginResult(userKey: "user2", displayName: "user2", avatarURL: nil))
        // The jar is replaced whole: the old identity and the multi-quote cookie are gone; page 5's refresh is kept.
        let cookies = await session.cookies(now: now).map { "\($0.name)=\($0.value)" }
        #expect(cookies == ["md_id=900002", "md_passs=refreshedpass", "md_user=user2"])
        #expect(await session.hashCheck == "REDACTED") // the anonymized token of R55-p5
        #expect(await session.userKey(now: now) == "user2")

        let requests = await jar.requests
        #expect(requests.count == 2)
        let post = try #require(requests.first)
        #expect(post.method == .post)
        #expect(post.url == Self.loginURL)
        // Trimmed pseudo, password as typed, field order of the captures (W03 meta).
        #expect(post.body.flatMap { String(bytes: $0, encoding: .utf8) }
            == "pseudo=user2&password=fake+password&action=send&login=Se+connecter")
        #expect(requests.last?.method == .get)
        #expect(requests.last?.url == Self.profileURL)
    }

    @Test func avatarComesFromTheProfilePage() async throws {
        var steps = try successSteps(user: "user1", profile: "R55-p5u1-profile-edit-page5-avatar")
        steps[0].reply = try page("W01b-login-success-user1", at: Self.loginURL)
        let (flow, _) = flow(ScriptedLoginJar(steps))
        let session = HFRSession()

        let result = try await flow.login(pseudo: "user1", password: "fake", into: session, now: now)

        #expect(result.avatarURL?.absoluteString == "https://forum-images.hardware.fr/images/mesdiscussions-900001.jpg")
        #expect(await session.userKey(now: now) == "user1")
    }

    @Test func expectedAccountIsAccepted() async throws {
        let (flow, _) = flow(ScriptedLoginJar(try successSteps()))
        let session = targetSession()
        let result = try await flow.login(pseudo: "user2", password: "fake", into: session, expectedUserKey: "user2", now: now)
        #expect(result.userKey == "user2")
        #expect(await session.userKey(now: now) == "user2")
    }

    // MARK: - Nothing changes unless the login is validated

    @Test func refusalLeavesTheSessionAlone() async throws {
        let jar = ScriptedLoginJar([.init(reply: try page("W01-login-failure", at: Self.loginURL))])
        let (flow, _) = flow(jar)
        let session = targetSession()

        await #expect(throws: LoginError.invalidCredentials) {
            try await flow.login(pseudo: "user1", password: "wrong", into: session, now: now)
        }
        await expectUnchanged(session)
        #expect(await jar.requests.count == 1) // no profile page after a refusal
    }

    /// The login form page `W00` stands for "any other page": it is not what HFR answers to the POST.
    @Test func unknownAnswerIsNotCalledARefusal() async throws {
        let jar = ScriptedLoginJar([.init(reply: try page("W00-login-form-anon", at: Self.loginURL))])
        let (flow, _) = flow(jar)
        let session = targetSession()

        await #expect(throws: LoginError.unrecognizedResponse) {
            try await flow.login(pseudo: "user1", password: "fake", into: session, now: now)
        }
        await expectUnchanged(session)
        #expect(await jar.requests.count == 1)
    }

    @Test(arguments: [[StoredCookie](), [StoredCookie(name: "md_user", value: "deleted", domain: ".hardware.fr")]])
    func successPageWithoutIdentityIsRefused(cookies: [StoredCookie]) async throws {
        let jar = ScriptedLoginJar([.init(reply: try page("W03-login-success", at: Self.loginURL), setCookies: cookies)])
        let (flow, _) = flow(jar)
        let session = targetSession()

        await #expect(throws: LoginError.missingIdentityCookie) {
            try await flow.login(pseudo: "user2", password: "fake", into: session, now: now)
        }
        await expectUnchanged(session)
        #expect(await jar.requests.count == 1)
    }

    @Test func anotherAccountIsRefused() async throws {
        let jar = ScriptedLoginJar(try successSteps(user: "user2"))
        let (flow, _) = flow(jar)
        let session = targetSession()

        await #expect(throws: LoginError.accountMismatch) {
            try await flow.login(pseudo: "user2", password: "fake", into: session, expectedUserKey: "olduser", now: now)
        }
        await expectUnchanged(session)
        #expect(await jar.requests.count == 1) // refused before reading the profile page
    }

    /// Page 5 sets `md_user` again (`R55-p5`): an identity changed or logged out by it must not be installed.
    @Test(arguments: [("user3", LoginError.accountMismatch), ("deleted", .missingIdentityCookie)])
    func identityChangedByTheProfilePageIsRefused(newValue: String, expected: LoginError) async throws {
        var steps = try successSteps(user: "user2")
        steps[1].setCookies = [forumCookie("md_user", newValue)]
        let (flow, _) = flow(ScriptedLoginJar(steps))
        let session = targetSession()

        await #expect(throws: expected) {
            try await flow.login(pseudo: "user2", password: "fake", into: session, expectedUserKey: "user2", now: now)
        }
        await expectUnchanged(session)
    }

    /// `W00` prints `hash_check` empty, as every logged-out page does (`R01`): stands for a profile page read without
    /// a working session.
    @Test func profilePageWithoutTokenIsRefused() async throws {
        var steps = try successSteps()
        steps[1].reply = try page("W00-login-form-anon", at: Self.profileURL)
        let (flow, _) = flow(ScriptedLoginJar(steps))
        let session = targetSession()

        await #expect(throws: LoginError.missingHashCheck) {
            try await flow.login(pseudo: "user2", password: "fake", into: session, now: now)
        }
        await expectUnchanged(session)
    }

    @Test(arguments: [0, 1])
    func networkFailureAtEitherStepLeavesTheSessionAlone(failingStep: Int) async throws {
        var steps = try successSteps()
        steps[failingStep].reply = .failure(.timedOut)
        let (flow, _) = flow(ScriptedLoginJar(steps))
        let session = targetSession()

        await #expect(throws: LoginError.network(.timedOut)) {
            try await flow.login(pseudo: "user2", password: "fake", into: session, now: now)
        }
        await expectUnchanged(session)
    }

    @Test func serverErrorOnTheProfilePageIsReported() async throws {
        var steps = try successSteps()
        steps[1].reply = .success(HTTPResponse(statusCode: 500, url: Self.profileURL))
        let (flow, _) = flow(ScriptedLoginJar(steps))
        let session = targetSession()

        await #expect(throws: LoginError.network(.httpStatus(code: 500, url: Self.profileURL))) {
            try await flow.login(pseudo: "user2", password: "fake", into: session, now: now)
        }
        await expectUnchanged(session)
    }

    @Test func cancelledLoginLeavesTheSessionAlone() async throws {
        var steps = try successSteps()
        steps[1].cancelsCaller = true
        let (flow, _) = flow(ScriptedLoginJar(steps))
        let session = targetSession()

        // A child task, so cancelling it does not cancel the test itself.
        let now = now
        let attempt = Task { try await flow.login(pseudo: "user2", password: "fake", into: session, now: now) }
        await #expect(throws: LoginError.network(.cancelled)) { try await attempt.value }
        await expectUnchanged(session)
    }

    @Test(arguments: [("", "fake"), (" \n\t", "fake"), ("user2", "")])
    func emptyCredentialsSendNothing(pseudo: String, password: String) async throws {
        let jar = ScriptedLoginJar(try successSteps())
        let (flow, factory) = flow(jar)
        let session = targetSession()

        await #expect(throws: LoginError.missingCredentials) {
            try await flow.login(pseudo: pseudo, password: password, into: session, now: now)
        }
        #expect(factory.jarsMade == 0)
        #expect(await jar.requests.isEmpty)
        await expectUnchanged(session)
    }
}
