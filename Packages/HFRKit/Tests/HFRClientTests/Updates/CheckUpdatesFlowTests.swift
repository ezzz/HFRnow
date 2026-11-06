import Foundation
import HFRModels
import HFRNetwork
import Testing
@testable import HFRClient
@testable import HFRNetwork

/// LOT-092: the check on the captured home pages (`R01`-`R03`, `R70a`) and flags pages (`R10`, `R12`, `R123g`, `R70b`).
@Suite("Check updates flow")
struct CheckUpdatesFlowTests {
    static let homeURL = URL(string: "https://forum.hardware.fr/") ?? URL(fileURLWithPath: "/")
    static let flagsURL = URL(string: "https://forum.hardware.fr/forum1f.php?owntopic=1") ?? URL(fileURLWithPath: "/")
    private static let expiry = Date().addingTimeInterval(86_400)

    private static func cookie(_ name: String, _ value: String) -> StoredCookie {
        StoredCookie(name: name, value: value, domain: ".hardware.fr", path: "/", expiresDate: expiry)
    }

    /// The jar of `R70a`'s meta: the account's `md_user` and `md_id`, a `md_passs` HFR may refuse.
    static func account() -> HFRSession {
        HFRSession(cookies: [cookie("md_user", "user2"), cookie("md_passs", "somepass"), cookie("md_id", "900002")])
    }

    /// A flow over scripted probes; every request is recorded, whichever probe got it.
    struct Ready {
        let flow: CheckUpdatesFlow
        let home: MockTransport
        let flags: MockTransport
        let account: HFRSession
    }

    static func ready(
        home: Result<HTTPResponse, NetworkError>, flags: Result<HTTPResponse, NetworkError>, account: HFRSession = account()
    ) -> Ready {
        let homeProbe = MockTransport(replies: [home])
        let flagsProbe = MockTransport(replies: [flags])
        let flow = CheckUpdatesFlow(
            readMessages: { () async throws(MPUnreadPollError) -> Int? in
                try await MPUnreadPoll(session: account, makeProbe: { _ in homeProbe }).unreadCount()
            },
            readFlags: { () async throws(FlaggedTopicsPollError) -> [TopicSummary]? in
                try await FlaggedTopicsPoll(session: account, makeProbe: { _ in flagsProbe }).flaggedTopics()
            }
        )
        return Ready(flow: flow, home: homeProbe, flags: flagsProbe, account: account)
    }

    static func home(_ capture: String, status: Int = 200) throws -> Result<HTTPResponse, NetworkError> {
        .success(try Capture.response(capture, url: homeURL, status: status))
    }

    static func flags(_ capture: String, status: Int = 200) throws -> Result<HTTPResponse, NetworkError> {
        .success(try Capture.response(capture, url: flagsURL, status: status))
    }

    @Test("Logged-in home and flags page: the count and the two flagged topics, most recent last post first")
    func bothAnswer() async throws {
        let ready = Self.ready(home: try Self.home("R02-home-logged-in-unread-mp"), flags: try Self.flags("R10-favourites-owntopic1"))
        let summary = try await ready.flow.check()
        #expect(summary.unreadPrivateMessages == .value(10))
        guard case .value(let topics) = summary.flaggedTopics else {
            Issue.record("flags did not answer: \(summary.flaggedTopics)")
            return
        }
        #expect(topics.map(\.title) == ["Followed topic 2", "Followed topic 1"])
    }

    @Test("Exactly two requests, `/` then `/forum1f.php?owntopic=1`, none to a topic page, none with a body")
    func requestsAreTheTwoListPages() async throws {
        let ready = Self.ready(home: try Self.home("R02-home-logged-in-unread-mp"), flags: try Self.flags("R10-favourites-owntopic1"))
        _ = try await ready.flow.check()
        let sent = await ready.home.requests + ready.flags.requests
        #expect(sent.map(\.url) == [Self.homeURL, Self.flagsURL])
        #expect(sent.allSatisfy { $0.method == .get && $0.body == nil })
        for request in sent {
            let text = request.url.absoluteString
            #expect(!text.contains("forum2.php") && !text.contains("sujet_") && !text.contains("/hfr/"))
        }
    }

    @Test("The flags request does not follow a redirect, so the cookies cannot be sent on to a topic page")
    func flagsRequestDoesNotFollow() async throws {
        let ready = Self.ready(home: try Self.home("R03-home-logged-in-no-unread-mp"), flags: try Self.flags("R10-favourites-owntopic1"))
        _ = try await ready.flow.check()
        #expect(await ready.flags.requests.first?.redirectPolicy == .doNotFollow)
    }

    @Test("A redirect answer on the flags page is an unreadable page, not an empty list")
    func flagsRedirectIsNotAnEmptyList() async throws {
        let ready = Self.ready(
            home: try Self.home("R02-home-logged-in-unread-mp"),
            flags: try Self.flags("R123g-favourites-owntopic1-empty-after-delflag", status: 302)
        )
        let summary = try await ready.flow.check()
        guard case .failed(.page(.malformed)) = summary.flaggedTopics else {
            Issue.record("expected a malformed outcome, got \(summary.flaggedTopics)")
            return
        }
        #expect(summary.unreadPrivateMessages == .value(10))
    }

    @Test("A confirmed empty list (`R123g`) is `.value([])`; the logged-out `.hop` (`R12`) is `noInformation`, not an empty list")
    func emptyListVersusLoggedOut() async throws {
        let empty = Self.ready(
            home: try Self.home("R03-home-logged-in-no-unread-mp"),
            flags: try Self.flags("R123g-favourites-owntopic1-empty-after-delflag")
        )
        let emptySummary = try await empty.flow.check()
        #expect(emptySummary.unreadPrivateMessages == .value(0))
        #expect(emptySummary.flaggedTopics == .value([]))

        let loggedOut = Self.ready(home: try Self.home("R01-home-anon"), flags: try Self.flags("R12-favourites-anon"))
        let outSummary = try await loggedOut.flow.check()
        #expect(outSummary.unreadPrivateMessages == .noInformation)
        #expect(outSummary.flaggedTopics == .noInformation)
    }

    @Test("A page of another kind on the flags URL is an unreadable page, never zero news")
    func otherPageIsMalformed() async throws {
        let ready = Self.ready(home: try Self.home("R02-home-logged-in-unread-mp"), flags: try Self.flags("R20-topic-p1-anon"))
        let summary = try await ready.flow.check()
        guard case .failed(.page(.malformed)) = summary.flaggedTopics else {
            Issue.record("expected a malformed outcome, got \(summary.flaggedTopics)")
            return
        }
    }

    @Test("The stale-session home (`R70a`) is `sessionExpired` for both sources and the flags page is never requested")
    func staleHomeSkipsTheFlags() async throws {
        let ready = Self.ready(home: try Self.home("R70a-home-stale-session"), flags: try Self.flags("R10-favourites-owntopic1"))
        let summary = try await ready.flow.check()
        #expect(summary.unreadPrivateMessages == .failed(.sessionExpired(.credentialsRefused)))
        #expect(summary.flaggedTopics == .failed(.sessionExpired(.credentialsRefused)))
        #expect(await ready.home.requests.count == 1)
        #expect(await ready.flags.requests.isEmpty)
    }

    @Test("The stale-session flags page (`R70b`) is `sessionExpired` for the flags only; the count stays")
    func staleFlagsPage() async throws {
        let ready = Self.ready(
            home: try Self.home("R02-home-logged-in-unread-mp"), flags: try Self.flags("R70b-favourites-owntopic1-stale-session")
        )
        let summary = try await ready.flow.check()
        #expect(summary.unreadPrivateMessages == .value(10))
        #expect(summary.flaggedTopics == .failed(.sessionExpired(.credentialsRefused)))
        #expect(await ready.account.cookies().first { $0.name == "md_passs" }?.value == "somepass")
    }

    @Test("A login adopted while the stale flags answer was in flight gets no verdict from it: no information")
    func loginDuringTheFlagsPoll() async throws {
        let account = Self.account()
        let stale = try Capture.response("R70b-favourites-owntopic1-stale-session", url: Self.flagsURL)
        let login = [Self.cookie("md_user", "user2"), Self.cookie("md_passs", "loginpass"), Self.cookie("md_id", "900002")]
        let probe = MockTransport { _ async throws(NetworkError) -> HTTPResponse in
            try? await account.adoptLogin(cookies: login, hashCheck: "newhash", now: Date())
            return stale
        }
        let poll = FlaggedTopicsPoll(session: account, makeProbe: { _ in probe })
        #expect(try await poll.flaggedTopics() == nil)
        #expect(await account.cookies().first { $0.name == "md_passs" }?.value == "loginpass")
    }

    @Test("A failing source does not hide the other: the flags answer after a home timeout, and the reverse")
    func oneFailureKeepsTheOther() async throws {
        let first = Self.ready(home: .failure(.timedOut), flags: try Self.flags("R10-favourites-owntopic1"))
        let firstSummary = try await first.flow.check()
        #expect(firstSummary.unreadPrivateMessages == .failed(.network(.timedOut)))
        #expect(firstSummary.flaggedTopics != .noInformation)
        #expect(await first.flags.requests.count == 1)

        let url = Self.flagsURL
        let second = Self.ready(
            home: try Self.home("R02-home-logged-in-unread-mp"), flags: .failure(.httpStatus(code: 503, url: url))
        )
        let secondSummary = try await second.flow.check()
        #expect(secondSummary.unreadPrivateMessages == .value(10))
        #expect(secondSummary.flaggedTopics == .failed(.network(.httpStatus(code: 503, url: url))))
    }

    @Test("Neither source touches the account session: same cookies, no token stored")
    func accountIsLeftAlone() async throws {
        let account = Self.account()
        let before = await account.cookies()
        let ready = Self.ready(
            home: try Self.home("R02-home-logged-in-unread-mp"), flags: try Self.flags("R10-favourites-owntopic1"), account: account
        )
        _ = try await ready.flow.check()
        #expect(await account.cookies() == before)
        #expect(await account.hashCheck == nil)
    }

    @Test("The default probes keep a loopback-only account's host policy, so a test session cannot reach the forum")
    func defaultProbesKeepTheHostPolicy() async {
        let loopback = SessionHostPolicy.exactHost("127.0.0.1")
        let account = HFRSession(cookies: [], hashCheck: nil, now: Date(), configuration: .ephemeral, hosts: loopback)
        let flags = FlaggedTopicsPoll(session: account).probe(cookies: []) as? HFRSession
        #expect(await flags?.hosts == loopback)
        let production = FlaggedTopicsPoll(session: HFRSession()).probe(cookies: []) as? HFRSession
        #expect(await production?.hosts == .forum)
        // The flags request itself is refused by that policy before any socket is opened.
        let refused = FlaggedTopicsPoll(session: account)
        await #expect(throws: FlaggedTopicsPollError.network(.invalidRequest(reason: "An account session only contacts hardware.fr"))) {
            try await refused.flaggedTopics()
        }
    }

    @Test("Cancelled before the first request: nothing is sent and nothing is returned")
    func cancelledBeforeStarting() async throws {
        let ready = Self.ready(home: try Self.home("R02-home-logged-in-unread-mp"), flags: try Self.flags("R10-favourites-owntopic1"))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ready.flow.check()
        }
        await #expect(throws: CheckUpdatesCancelled()) { try await task.value }
        #expect(await ready.home.requests.isEmpty)
        #expect(await ready.flags.requests.isEmpty)
    }

    @Test("Cancelled while the home page is in flight: no flags request, no partial summary")
    func cancelledDuringTheHome() async throws {
        let page = try Capture.response("R02-home-logged-in-unread-mp", url: Self.homeURL)
        let home = MockTransport { _ async throws(NetworkError) -> HTTPResponse in
            withUnsafeCurrentTask { $0?.cancel() }
            return page
        }
        let flags = MockTransport(replies: [try Self.flags("R10-favourites-owntopic1")])
        let account = Self.account()
        let flow = CheckUpdatesFlow(
            readMessages: { () async throws(MPUnreadPollError) -> Int? in
                try await MPUnreadPoll(session: account, makeProbe: { _ in home }).unreadCount()
            },
            readFlags: { () async throws(FlaggedTopicsPollError) -> [TopicSummary]? in
                try await FlaggedTopicsPoll(session: account, makeProbe: { _ in flags }).flaggedTopics()
            }
        )
        let task = Task { try await flow.check() }
        await #expect(throws: CheckUpdatesCancelled()) { try await task.value }
        #expect(await flags.requests.isEmpty)
    }

    @Test("Cancelled while the flags page is in flight: the count that had answered is not returned alone")
    func cancelledDuringTheFlags() async throws {
        let page = try Capture.response("R10-favourites-owntopic1", url: Self.flagsURL)
        let flags = MockTransport { _ async throws(NetworkError) -> HTTPResponse in
            withUnsafeCurrentTask { $0?.cancel() }
            return page
        }
        let home = MockTransport(replies: [try Self.home("R02-home-logged-in-unread-mp")])
        let account = Self.account()
        let flow = CheckUpdatesFlow(
            readMessages: { () async throws(MPUnreadPollError) -> Int? in
                try await MPUnreadPoll(session: account, makeProbe: { _ in home }).unreadCount()
            },
            readFlags: { () async throws(FlaggedTopicsPollError) -> [TopicSummary]? in
                try await FlaggedTopicsPoll(session: account, makeProbe: { _ in flags }).flaggedTopics()
            }
        )
        let task = Task { try await flow.check() }
        await #expect(throws: CheckUpdatesCancelled()) { try await task.value }
    }

    @Test("`flaggedTopics(postedAfter:)` keeps later and undated topics and is nil when the flags did not answer")
    func newsSinceADate() throws {
        func topic(_ title: String, _ date: Date?) -> TopicSummary {
            var row = TopicSummary(title: title, path: "/x")
            row.lastPost = date.map { LastPost(author: "a", path: "/x#bas", date: $0) }
            return row
        }
        let moment = Date(timeIntervalSince1970: 1_000)
        let topics = [
            topic("later", moment.addingTimeInterval(1)), topic("same", moment), topic("older", moment.addingTimeInterval(-1)),
            topic("undated", nil)
        ]
        var summary = UpdateSummary(unreadPrivateMessages: .noInformation, flaggedTopics: .value(topics))
        #expect(summary.flaggedTopics(postedAfter: moment)?.map(\.title) == ["later", "undated"])
        summary.flaggedTopics = .value([])
        #expect(summary.flaggedTopics(postedAfter: moment) == [])
        for other in [UpdateOutcome<[TopicSummary]>.noInformation, .failed(.sessionExpired(.credentialsRefused))] {
            summary.flaggedTopics = other
            #expect(summary.flaggedTopics(postedAfter: moment) == nil)
        }
    }
}
