import Foundation
import HFRModels
@testable import HFRNetwork
import Testing
@testable import HFRClient

/// #869, option A (operator, 2026-11-28): a list row has no `addflag.php` link, so « Ajouter aux favoris » checks the
/// session, reads the row's last page (`R21`) and follows the `addflag` link of its last message (answered `P03a`). The
/// scripted session counts every request it is asked: one page GET and one `addflag` GET per add, nothing else, and no
/// write without a confirmed session or without that link. Cookie values are fake.
@Suite("Favourite added from a list (#869)")
struct FlagAddFromListTests {
    static let cuisine = TopicID(category: .forum(13), topic: 28563)
    static let token = "fake-token-0123"
    private let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))

    /// The `addflag` link of `R21`'s last message (`ref=40`), the one the add must follow.
    static func lastMessageLink() throws -> URL {
        try #require(try FlagCapture.links(in: "R21-topic-p1-logged-in", path: "/user/addflag.php").last)
    }

    private static func run(
        _ session: ScriptedFlagSession, topic: TopicID = cuisine, page: Int = 1,
        check: TopicFlagFlow.SessionCheck = { () async throws(NetworkError) -> SessionHealth in .valid }
    ) async -> Result<TopicFlagResult, TopicFlagError> {
        do throws(TopicFlagError) {
            return .success(try await TopicFlagFlow().addFavorite(topic, fromLastMessageOfPage: page, through: session, after: check))
        } catch {
            return .failure(error)
        }
    }

    @Test("A confirmed session sends one page GET, then one GET of its last message's addflag link, confirmed by P03a")
    func onePageReadAndOneWrite() async throws {
        let session = ScriptedFlagSession([try FlagCapture.page("R21"), try FlagCapture.page("P03a")], hashCheck: Self.token)
        let result = try await Self.run(session).get()
        #expect(result.action == .addFavorite && result.topic == Self.cuisine)
        #expect(result.message == "Favori positionné avec succès")
        let requests = await session.requests
        #expect(requests.map(\.method) == [.get, .get])
        #expect(requests.map(\.url) == [try HFREndpoint.topicPage(topic: Self.cuisine, page: 1).url, try Self.lastMessageLink()])
        // Not the first message's link (`P03a`'s own request): the add sits on the page's last message.
        #expect(requests.last?.url != (try FlagCapture.requestURL("P03a")))
    }

    @Test("The row's page is the one read: HFR redirects a page past the end to the last one (R24)")
    func theRowsPageIsRead() async throws {
        let session = ScriptedFlagSession([try FlagCapture.page("R21"), try FlagCapture.page("P03a")], hashCheck: Self.token)
        _ = try await Self.run(session, page: 7).get()
        #expect(await session.requests.first?.url == (try HFREndpoint.topicPage(topic: Self.cuisine, page: 7).url))
    }

    @Test(
        "A session the check does not confirm reads no page and sends no write",
        arguments: [SessionHealth.expired(.noIdentityCookie), .unconfirmed(.unrecognizedPage), .expired(.credentialsRefused)]
    )
    func unconfirmedSessionAsksNothing(health: SessionHealth) async throws {
        let session = ScriptedFlagSession([try FlagCapture.page("R21"), try FlagCapture.page("P03a")], hashCheck: Self.token)
        let result = await Self.run(session) { () async throws(NetworkError) -> SessionHealth in health }
        #expect(result.failure == .sessionNotConfirmed(health))
        #expect(await session.requests.isEmpty)
    }

    @Test(
        "A page without an addflag link on its last message sends no write: the anonymous topic page, a page that is no topic",
        arguments: ["R20", "P03a", "R12"]
    )
    func missingLinkSendsNoWrite(page: String) async throws {
        let session = ScriptedFlagSession([try FlagCapture.page(page), try FlagCapture.page("P03a")], hashCheck: Self.token)
        let result = await Self.run(session)
        #expect(result.failure == .favoriteLinkMissing)
        #expect(await session.requests.count == 1)
    }

    @Test("Another topic's page gives no link of this topic: no write")
    func anotherTopicsLinkIsNotFollowed() async throws {
        let session = ScriptedFlagSession([try FlagCapture.page("R21"), try FlagCapture.page("P03a")], hashCheck: Self.token)
        let result = await Self.run(session, topic: TopicID(category: .forum(13), topic: 99))
        #expect(result.failure == .favoriteLinkMissing)
        #expect(await session.requests.count == 1)
    }

    @Test("A page read that fails is a network failure, and no write is sent", arguments: [NetworkError.offline, .timedOut])
    func failedPageReadSendsNoWrite(failure: NetworkError) async throws {
        let session = ScriptedFlagSession([.failure(failure), try FlagCapture.page("P03a")], hashCheck: Self.token)
        let result = await Self.run(session)
        #expect(result.failure == .network(failure))
        #expect(await session.requests.count == 1)
    }

    @Test("A login landing during the check reads no page either: another account's read flag never moves (#869 review)")
    func loginDuringTheCheckReadsNoPage() async throws {
        let session = ScriptedFlagSession([try FlagCapture.page("R21"), try FlagCapture.page("P03a")], hashCheck: Self.token)
        let result = await Self.run(session) { () async throws(NetworkError) -> SessionHealth in
            await session.adoptLogin(ConcurrentLogin(identity: "user2", hashCheck: "fake-token-other"))
            return .valid
        }
        #expect(result.failure == .sessionChanged)
        #expect(await session.requests.isEmpty)
    }

    @Test("A topic page served off the forum host (another hardware.fr host the session may follow) gives no link: no write")
    func aPageOffTheForumHostIsNotRead() async throws {
        let offForum = try #require(URL(string: "https://www.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm"))
        let page = try Capture.response("R21-topic-p1-logged-in", url: offForum)
        let session = ScriptedFlagSession([.success(page), try FlagCapture.page("P03a")], hashCheck: Self.token)
        let result = await Self.run(session)
        #expect(result.failure == .favoriteLinkMissing)
        #expect(await session.requests.count == 1)
    }

    @Test("A login landing during the page read sends no write (#1200 P2)")
    func loginDuringThePageReadSendsNoWrite() async throws {
        let session = ScriptedFlagSession([try FlagCapture.page("R21"), try FlagCapture.page("P03a")], hashCheck: Self.token)
        await session.adoptLoginDuringNextRequest(ConcurrentLogin(identity: "user2", hashCheck: "fake-token-other"))
        let result = await Self.run(session)
        #expect(result.failure == .sessionChanged)
        #expect(await session.requests.count == 1)
    }

    @Test(
        "An invalid topic or page asks nothing, not even the check",
        arguments: [
            (TopicID(category: .privateMessages, topic: 5), 1), (TopicID(category: .forum(13), topic: 0), 1), (cuisine, 0)
        ] as [(TopicID, Int)]
    )
    func invalidInputAsksNothing(topic: TopicID, page: Int) async throws {
        let session = ScriptedFlagSession([try FlagCapture.page("R21")], hashCheck: Self.token)
        let checks = Counter()
        let result = await Self.run(session, topic: topic, page: page) { () async throws(NetworkError) -> SessionHealth in
            await checks.increment()
            return .valid
        }
        #expect(result.failure == .invalidTopic)
        #expect(await checks.value == 0)
        #expect(await session.requests.isEmpty)
    }

    @Test("The public entry point checks the session first: a session that never logged in asks nothing of HFR")
    func publicEntryPointIsGated() async throws {
        // This session may only contact the loopback host: whatever it is asked, nothing can reach HFR.
        let session = HFRSession(
            cookies: [], hashCheck: Self.token, now: now, configuration: .ephemeral, hosts: .exactHost("127.0.0.1")
        )
        await #expect(throws: TopicFlagError.sessionNotConfirmed(.expired(.noIdentityCookie))) {
            try await TopicFlagFlow().addFavorite(Self.cuisine, fromLastMessageOfPage: 1, in: session)
        }
    }
}

/// Counts the session checks a flow asked for.
private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

extension Result {
    /// The failure, nil on success.
    fileprivate var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
