import Foundation
import HFRModels
import HFRNetwork
import Testing
@testable import HFRClient

/// LOT-047: the poll on the captured home pages (`R01`-`R03`), checked against the legacy oracle's `nbMP`.
@Suite("Private messages unread poll")
struct MPUnreadPollTests {
    private static let homeURL = URL(string: "https://forum.hardware.fr/") ?? URL(fileURLWithPath: "/")

    /// What the probe factory was given.
    final class Seeds: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [[StoredCookie]] = []
        func add(_ cookies: [StoredCookie]) { lock.lock(); all.append(cookies); lock.unlock() }
        var values: [[StoredCookie]] { lock.lock(); defer { lock.unlock() }; return all }
    }

    private static let cookies = [
        StoredCookie(name: "md_user", value: "fakeuser", domain: ".hardware.fr", path: "/", expiresDate: Date().addingTimeInterval(86_400)),
        StoredCookie(name: "md_passs", value: "fakepass", domain: ".hardware.fr", path: "/", expiresDate: Date().addingTimeInterval(86_400))
    ]

    /// A poll with its scripted probe and the account session it reads.
    struct Ready {
        let poll: MPUnreadPoll
        let probe: MockTransport
        let seeds: Seeds
        let account: HFRSession
    }

    private func poll(
        _ reply: Result<HTTPResponse, NetworkError>, account: HFRSession = HFRSession(cookies: MPUnreadPollTests.cookies)
    ) -> Ready {
        let probe = MockTransport(replies: [reply])
        let seeds = Seeds()
        let poll = MPUnreadPoll(session: account, makeProbe: { seeds.add($0); return probe })
        return Ready(poll: poll, probe: probe, seeds: seeds, account: account)
    }

    private func html(_ body: String) -> Result<HTTPResponse, NetworkError> {
        .success(HTTPResponse(
            statusCode: 200, headers: ["Content-Type": "text/html; charset=utf-8"], url: Self.homeURL, body: Data(body.utf8)
        ))
    }

    @Test("The count of each captured home page is the legacy oracle's `nbMP`; logged out is nil", arguments: [
        ("R01", "R01-home-anon", nil as Int?),
        ("R02", "R02-home-logged-in-unread-mp", 10),
        ("R03", "R03-home-logged-in-no-unread-mp", 0)
    ])
    func homePages(oracle: String, capture: String, expected: Int?) async throws {
        #expect(try Capture.legacyUnreadCount(oracle) == expected)
        let ready = poll(.success(try Capture.response(capture, url: Self.homeURL)))
        #expect(try await ready.poll.unreadCount() == expected)
    }

    @Test("One GET of the home page through the probe with the 5 s background timeout, no topic page")
    func requestsOnlyTheHomePage() async throws {
        let ready = poll(.success(try Capture.response("R02-home-logged-in-unread-mp", url: Self.homeURL)))
        _ = try await ready.poll.unreadCount()
        let sent = await ready.probe.requests
        #expect(sent.count == 1)
        #expect(sent.first?.method == .get)
        #expect(sent.first?.url == Self.homeURL)
        #expect(sent.first?.timeout == RequestTimeout.background)
    }

    @Test("The probe starts from exactly the account's cookies, and the account session is left unchanged")
    func probeIsSeededAndAccountUntouched() async throws {
        let ready = poll(.success(try Capture.response("R02-home-logged-in-unread-mp", url: Self.homeURL)))
        let before = await ready.account.cookies()
        _ = try await ready.poll.unreadCount()
        #expect(ready.seeds.values == [before])
        #expect(!before.isEmpty)
        #expect(await ready.account.cookies() == before)
        #expect(await ready.account.hashCheck == nil)
    }

    @Test("An answer that sets cookies, landing after the account logged in again, does not overwrite the new cookies")
    func staleAnswerDoesNotOverwriteAccount() async throws {
        let account = HFRSession(cookies: Self.cookies)
        let expiry = Date().addingTimeInterval(86_400)
        let fresh = StoredCookie(name: "md_passs", value: "freshpass", domain: ".hardware.fr", path: "/", expiresDate: expiry)
        let stale = StoredCookie(name: "md_passs", value: "stalepass", domain: ".hardware.fr", path: "/", expiresDate: expiry)
        let reply = try Capture.response("R02-home-logged-in-unread-mp", url: Self.homeURL)
        // A stateful probe: like HFRSession, it stores the cookies the answer sets; a login lands while the GET is in flight.
        let probeJar = HFRSession(cookies: Self.cookies)
        let probe = MockTransport { _ async throws(NetworkError) -> HTTPResponse in
            await account.mergeCookies([fresh])
            await probeJar.mergeCookies([stale])
            return reply
        }
        let poll = MPUnreadPoll(session: account, makeProbe: { _ in probe })
        #expect(try await poll.unreadCount() == 10)
        let held = await account.cookies().first { $0.name == "md_passs" }
        #expect(held?.value == "freshpass")
        let probed = await probeJar.cookies().first { $0.name == "md_passs" }
        #expect(probed?.value == "stalepass")
    }

    @Test("A page that is not the home page or a forum list says nothing (nil), not 0: the MP list, a topic page", arguments: [
        "R13a-mp-list", "R20-topic-p1-anon"
    ])
    func otherPagesAreNoInformation(_ capture: String) async throws {
        let ready = poll(.success(try Capture.response(capture, url: Self.homeURL)))
        #expect(try await ready.poll.unreadCount() == nil)
    }

    @Test("A maintenance page throws instead of reading as logged out")
    func maintenance() async {
        let ready = poll(html("<html><body><p>Maintenance en cours</p></body></html>"))
        await #expect(throws: MPUnreadPollError.page(.maintenance("Maintenance en cours"))) {
            try await ready.poll.unreadCount()
        }
    }

    @Test("Transport failures and HTTP errors throw `.network`", arguments: [
        NetworkError.timedOut, .offline, .httpStatus(code: 503, url: URL(string: "https://forum.hardware.fr/") ?? URL(fileURLWithPath: "/"))
    ])
    func networkFailures(_ failure: NetworkError) async {
        let ready = poll(.failure(failure))
        await #expect(throws: MPUnreadPollError.network(failure)) { try await ready.poll.unreadCount() }
    }

    @Test("A status of 500 is not read as a page")
    func serverErrorIsNotAPage() async throws {
        let body = try Capture.page("R03-home-logged-in-no-unread-mp")
        let reply = Result<HTTPResponse, NetworkError>.success(HTTPResponse(
            statusCode: 500, headers: ["Content-Type": "text/html; charset=utf-8"], url: Self.homeURL, body: Data(body.utf8)
        ))
        let ready = poll(reply)
        await #expect(throws: MPUnreadPollError.network(.httpStatus(code: 500, url: Self.homeURL))) {
            try await ready.poll.unreadCount()
        }
    }

    @Test("A poll started on a cancelled task sends nothing")
    func cancelledBeforeStart() async throws {
        let ready = poll(.success(try Capture.response("R02-home-logged-in-unread-mp", url: Self.homeURL)))
        let task = Task {
            // Cancelled before the first suspension point of the child.
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ready.poll.unreadCount()
        }
        await #expect(throws: MPUnreadPollError.network(.cancelled)) { try await task.value }
        #expect(await ready.probe.requests.isEmpty)
    }
}
