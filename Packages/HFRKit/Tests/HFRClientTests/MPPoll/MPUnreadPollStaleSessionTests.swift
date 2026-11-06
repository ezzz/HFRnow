import Foundation
import HFRModels
import HFRNetwork
import Testing
@testable import HFRClient

/// #383: the poll on HFR's answer to stale cookies (`R70a`), reported as `SessionRefreshFlow` reports `R70c`.
@Suite("Private messages unread poll: stale session")
struct MPUnreadPollStaleSessionTests {
    private static let homeURL = URL(string: "https://forum.hardware.fr/") ?? URL(fileURLWithPath: "/")
    private static let expiry = Date().addingTimeInterval(86_400)

    private static func cookie(_ name: String, _ value: String) -> StoredCookie {
        StoredCookie(name: name, value: value, domain: ".hardware.fr", path: "/", expiresDate: expiry)
    }

    /// The jar of `R70a`'s meta: the account's `md_user` and `md_id`, a `md_passs` HFR refuses.
    private static func account() -> HFRSession {
        HFRSession(cookies: [cookie("md_user", "user2"), cookie("md_passs", "stalepass"), cookie("md_id", "900002")])
    }

    private static func stalePage(at url: URL = homeURL) throws -> HTTPResponse {
        try Capture.response("R70a-home-stale-session", url: url)
    }

    @Test("The capture is the home page answered to a stale jar: 200, no redirect, no cookie")
    func captureMeta() throws {
        let meta = try Capture.meta("R70a")
        #expect(meta.method == "GET")
        #expect(meta.url == Self.homeURL.absoluteString)
        #expect(meta.finalURL == Self.homeURL.absoluteString)
        #expect(meta.status == 200)
        #expect(meta.setCookieNames.isEmpty)
    }

    @Test("HFR's stale-session home throws `.sessionExpired`, sends one GET and leaves the account as it was")
    func staleHomeIsExpired() async throws {
        let account = Self.account()
        let before = await account.cookies()
        let probe = MockTransport(replies: [.success(try Self.stalePage())])
        let poll = MPUnreadPoll(session: account, makeProbe: { _ in probe })

        await #expect(throws: MPUnreadPollError.sessionExpired(.credentialsRefused)) { try await poll.unreadCount() }
        #expect(await probe.requests.map(\.url) == [Self.homeURL])
        #expect(await account.cookies() == before)
        #expect(await account.hashCheck == nil)
    }

    @Test("The cookie-less `.hop` of the profile pages, served at `/`, is still no information", arguments: [
        "R71b-profile-edit-page1-anon", "R12-favourites-anon", "R01-home-anon"
    ])
    func otherLoggedOutPagesStayNil(_ capture: String) async throws {
        let probe = MockTransport(replies: [.success(try Capture.response(capture, url: Self.homeURL))])
        let poll = MPUnreadPoll(session: Self.account(), makeProbe: { _ in probe })
        #expect(try await poll.unreadCount() == nil)
    }

    @Test("The stale page served at another URL than the one requested, or with a redirect status, is no information")
    func stalePageElsewhereStaysNil() async throws {
        let other = URL(string: "https://forum.hardware.fr/user/editprofil.php?config=hfr.inc&page=1") ?? Self.homeURL
        for reply in [
            try Self.stalePage(at: other),
            try Capture.response("R70a-home-stale-session", url: Self.homeURL, status: 302)
        ] {
            let probe = MockTransport(replies: [.success(reply)])
            let poll = MPUnreadPoll(session: Self.account(), makeProbe: { _ in probe })
            #expect(try await poll.unreadCount() == nil)
        }
    }

    @Test("A login adopted while the stale answer was in flight gets no verdict from it")
    func loginDuringThePollIsNotExpired() async throws {
        let account = Self.account()
        let page = try Self.stalePage()
        let login = [Self.cookie("md_user", "user2"), Self.cookie("md_passs", "loginpass"), Self.cookie("md_id", "900002")]
        let probe = MockTransport { _ async throws(NetworkError) -> HTTPResponse in
            try? await account.adoptLogin(cookies: login, hashCheck: "newhash", now: Date())
            return page
        }
        let poll = MPUnreadPoll(session: account, makeProbe: { _ in probe })

        #expect(try await poll.unreadCount() == nil)
        #expect(await account.cookies().first { $0.name == "md_passs" }?.value == "loginpass")
    }

    @Test("A poll cancelled while the stale answer arrives throws `.network(.cancelled)`, not an expiry")
    func cancelledDuringTheStaleAnswer() async throws {
        let page = try Self.stalePage()
        let probe = MockTransport { _ async throws(NetworkError) -> HTTPResponse in
            withUnsafeCurrentTask { $0?.cancel() }
            return page
        }
        let poll = MPUnreadPoll(session: Self.account(), makeProbe: { _ in probe })
        let task = Task { try await poll.unreadCount() }
        await #expect(throws: MPUnreadPollError.network(.cancelled)) { try await task.value }
    }
}
