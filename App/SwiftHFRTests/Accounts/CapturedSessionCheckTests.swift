import Foundation
// The probe seam of `SessionRefreshFlow` is internal (LOT-044): Debug builds of the package are testable, so the app
// tests reach it the way the engine tests do, without a public test API.
@testable import HFRClient
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Synchronization
import Testing

/// What the forum answers one probe: a committed LOT-001 capture (or a transport failure) and the cookies it sets.
struct CapturedAnswer: Sendable {
    let reply: Result<HTTPResponse, NetworkError>
    var setCookies: [StoredCookie] = []

    static let profilePage1 = URL(string: "https://forum.hardware.fr/user/editprofil.php?config=hfr.inc&page=1")
        ?? URL(fileURLWithPath: "/")

    /// A capture served at profile page 1, as HFR served it (every capture used here is UTF-8 HTML).
    static func capture(_ file: String, status: Int = 200) throws -> HTTPResponse {
        HTTPResponse(
            statusCode: status, headers: ["Content-Type": "text/html; charset=utf-8"], url: profilePage1,
            body: try LiveTopicPageSourceTests.capture(file + ".html")
        )
    }

    static func cookie(_ name: String, _ value: String) -> StoredCookie {
        StoredCookie(name: name, value: value, domain: ".hardware.fr", expiresDate: Fake.tomorrow)
    }

    /// `R55-p1`, the logged-in profile page 1, with the cookies its meta says it sets (`md_user` again, `md_passs`).
    static func profilePage(identity: String) throws -> CapturedAnswer {
        CapturedAnswer(
            reply: .success(try capture("R55-p1-profile-edit-page1")),
            setCookies: [cookie("md_user", identity), cookie("md_passs", "refreshed-pass")]
        )
    }

    /// A page that is not the logged-in profile page; it still resets `md_passs`, which must not reach the session.
    static func page(_ file: String) throws -> CapturedAnswer {
        CapturedAnswer(reply: .success(try capture(file)), setCookies: [cookie("md_passs", "refreshed-pass")])
    }

    static func failure(_ error: NetworkError) -> CapturedAnswer {
        CapturedAnswer(reply: .failure(error))
    }
}

/// The forum as the LOT-044 probes see it: answers each account (keyed by the probe's seeded `md_user`) with its
/// scripted answers in order, the last one repeating, and records what was sent. Nothing leaves the process.
final class CapturedForum: Sendable {
    struct Sent: Sendable, Equatable {
        let user: String
        let url: URL
    }

    private let state: Mutex<(answers: [String: [CapturedAnswer]], sent: [Sent])>

    init(_ answers: [String: [CapturedAnswer]]) {
        state = Mutex((answers, []))
    }

    /// Requests sent, in order.
    var sent: [Sent] { state.withLock { $0.sent } }

    /// The real flow with this forum behind its probes.
    var flow: SessionRefreshFlow {
        SessionRefreshFlow { [self] cookies, now in CapturedProbe(seed: cookies, now: now, forum: self) }
    }

    fileprivate func answer(_ request: HTTPRequest, user: String) -> CapturedAnswer {
        state.withLock { state in
            state.sent.append(Sent(user: user, url: request.url))
            var queue = state.answers[user] ?? []
            let answer = queue.count > 1 ? queue.removeFirst() : queue.first ?? .failure(.unscripted)
            state.answers[user] = queue
            return answer
        }
    }
}

/// A probe jar whose cookies are a real `HFRSession` that never sends anything (as `ScriptedProbe` in the engine
/// tests): cookie merging and `userKey(now:)` are the production rules.
actor CapturedProbe: SessionJar {
    private let jar: HFRSession
    private let user: String
    private let now: Date
    private let forum: CapturedForum

    init(seed: [StoredCookie], now: Date, forum: CapturedForum) {
        self.jar = HFRSession(cookies: seed, now: now)
        self.user = seed.first { $0.name == HFRSession.identityCookieName }?.value ?? ""
        self.now = now
        self.forum = forum
    }

    func perform(_ request: HTTPRequest) async throws(NetworkError) -> HTTPResponse {
        let answer = forum.answer(request, user: user)
        await jar.mergeCookies(answer.setCookies, now: now)
        return try answer.reply.get()
    }

    func cookies(now: Date) async -> [StoredCookie] {
        await jar.cookies(now: now)
    }

    func userKey(now: Date) async -> String? {
        await jar.userKey(now: now)
    }
}

/// The accounts model on the real `SessionRefreshFlow`, answered with the LOT-044 captures (#300): only the transport
/// under the flow's probe is scripted. Stale cookies are not captured yet (#281): logged-out pages and an answer that
/// does not keep `md_user` stand in for them, as in `SessionRefreshFlowTests`.
@MainActor
struct CapturedSessionCheckTests {
    struct Restored {
        let model: AccountsModel
        let store: InMemoryCredentialStore
        let forum: CapturedForum
    }

    /// Restores `accounts` (the first one main) with the forum answering `answers`.
    private func restored(_ answers: [String: [CapturedAnswer]], accounts: [String] = ["user1"]) async throws -> Restored {
        let store = try InMemoryCredentialStore(
            accounts: accounts.enumerated().map { Fake.account($0.element, main: $0.offset == 0) }
        )
        let forum = CapturedForum(answers)
        let model = makeModel(store: store, checker: ForumSessionCheck(refresher: forum.flow))
        await model.restore()
        return Restored(model: model, store: store, forum: forum)
    }

    /// The account's session and stored copy are exactly what was stored before the check, and it is still logged in.
    private func expectKept(_ run: Restored, user: String) async throws {
        let session = try #require(run.model.session(for: user))
        #expect(await session.isLoggedIn())
        #expect(await session.cookies().map(\.value).sorted() == ["fake-pass", user])
        #expect(await session.hashCheck == "fake-hash")
        let stored = try #require(try run.store.accounts().first { $0.pseudo == user })
        #expect(stored.cookies == Fake.account(user).cookies)
        #expect(stored.hashCheck == "fake-hash")
    }

    @Test func capturedProfilePageConfirmsTheSessionAndPersistsItsRefresh() async throws {
        let run = try await restored(["user1": [.profilePage(identity: "user1")]])

        #expect(run.forum.sent == [.init(user: "user1", url: CapturedAnswer.profilePage1)])
        #expect(run.model.rows.map(\.status) == [.valid])
        // What R55-p1 set, and its (anonymized) token, reach the session and the store.
        let session = try #require(run.model.session(for: "user1"))
        #expect(await session.cookies().first { $0.name == "md_passs" }?.value == "refreshed-pass")
        #expect(await session.hashCheck == "REDACTED")
        let stored = try #require(try run.store.mainAccount())
        #expect(stored.cookies.first { $0.name == "md_passs" }?.value == "refreshed-pass")
        #expect(stored.hashCheck == "REDACTED")
    }

    /// Stand-ins for the uncaptured stale-cookie answer (#281): a logged-out page (`W00`), and the profile page whose
    /// answer sets `md_user=deleted` (#283). The forum was asked, nothing is concluded, the account stays logged in.
    @Test(arguments: ["W00-login-form-anon", "R55-p1 md_user=deleted"])
    func staleCookieStandInsKeepTheSessionLoggedIn(_ standIn: String) async throws {
        let answer: CapturedAnswer
        if standIn == "W00-login-form-anon" {
            answer = try .page(standIn)
        } else {
            answer = try .profilePage(identity: HFRSession.loggedOutMarker)
        }
        let run = try await restored(["user1": [answer]])

        #expect(run.forum.sent.map(\.user) == ["user1"])
        #expect(run.model.rows.map(\.status) == [.restored])
        try await expectKept(run, user: "user1")
    }

    /// Pages that are not the profile page: a `.hop` notice (`R12`), a `.hop` refusal echoing a token (`W17c`), the
    /// logged-out home (`R01`).
    @Test(arguments: ["R12-favourites-anon", "W17c-mp-reply-logged-out-rejected", "R01-home-anon"])
    func unknownPagesKeepTheSessionLoggedIn(_ file: String) async throws {
        let run = try await restored(["user1": [.page(file)]])

        #expect(run.forum.sent.map(\.user) == ["user1"])
        #expect(run.model.rows.map(\.status) == [.restored])
        try await expectKept(run, user: "user1")
    }

    @Test func networkErrorsAreReportedAndKeepTheSession() async throws {
        let serverError = CapturedAnswer(
            reply: .success(try CapturedAnswer.capture("R55-p1-profile-edit-page1", status: 500)),
            setCookies: [CapturedAnswer.cookie("md_passs", "refreshed-pass")]
        )
        let run = try await restored(
            ["user1": [.failure(.offline)], "user2": [.failure(.timedOut)], "user3": [serverError]],
            accounts: ["user1", "user2", "user3"]
        )

        #expect(run.forum.sent.map(\.user) == ["user1", "user2", "user3"])
        #expect(run.model.rows.map(\.status) == [
            .checkFailed(.offline), .checkFailed(.timedOut),
            .checkFailed(.httpStatus(code: 500, url: CapturedAnswer.profilePage1))
        ])
        for user in ["user1", "user2", "user3"] {
            try await expectKept(run, user: user)
        }
    }

    /// The quiet re-check goes through the same flow: a failed launch check is retried and the captured profile page
    /// then confirms the session.
    @Test func recheckAfterANetworkErrorConfirmsOnTheCapturedProfilePage() async throws {
        let run = try await restored(["user1": [.failure(.offline), .profilePage(identity: "user1")]])
        #expect(run.model.rows.map(\.status) == [.checkFailed(.offline)])

        await run.model.recheckUnconfirmedSessions(now: Date().addingTimeInterval(AccountsModel.recheckInterval + 1))

        #expect(run.forum.sent.map(\.user) == ["user1", "user1"])
        #expect(run.model.rows.map(\.status) == [.valid])
        #expect(try run.store.mainAccount()?.hashCheck == "REDACTED")
    }
}
