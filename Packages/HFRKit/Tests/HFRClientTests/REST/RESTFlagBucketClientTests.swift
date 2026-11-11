import Foundation
import HFRModels
@testable import HFRNetwork
import HFRParsing
import Testing
@testable import HFRClient

/// The flag bucket client over scripted probes: the captured requests, the account's cookies only read, the favourites page
/// as fallback (LOT-057).
@Suite("REST flag bucket client (LOT-057)")
struct RESTFlagBucketClientTests {
    private static let expiry = Date().addingTimeInterval(86_400)
    static let flagsURL = URL(string: "https://forum.hardware.fr/forum1f.php?owntopic=1") ?? URL(fileURLWithPath: "/")

    private static func cookie(_ name: String, _ value: String) -> StoredCookie {
        StoredCookie(name: name, value: value, domain: ".hardware.fr", path: "/", expiresDate: expiry)
    }

    static func account() -> HFRSession {
        HFRSession(cookies: [cookie("md_user", "user2"), cookie("md_passs", "somepass"), cookie("md_id", "900002")])
    }

    /// The cookies each probe was seeded with, in order; written from the client's synchronous probe factory.
    final class Seeds: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [[StoredCookie]] = []
        var values: [[StoredCookie]] { lock.withLock { stored } }
        func append(_ cookies: [StoredCookie]) { lock.withLock { stored.append(cookies) } }
    }

    /// What a call returned, sent and seeded its probe with.
    struct Run {
        let result: Result<RESTBrowsingResult<FavoritesPage>, RESTBrowsingError>
        let requests: [HTTPRequest]
        let seeds: [[StoredCookie]]
    }

    private static func run(
        _ bucket: RESTFlagBucket, _ replies: [Result<HTTPResponse, NetworkError>], account: HFRSession = account()
    ) async -> Run {
        let probe = MockTransport(replies: replies)
        let seeds = Seeds()
        let client = RESTFlagBucketClient(session: account, makeProbe: { cookies in
            seeds.append(cookies)
            return probe
        })
        let result: Result<RESTBrowsingResult<FavoritesPage>, RESTBrowsingError>
        do {
            result = .success(try await client.topics(in: bucket, postsPerPage: 40))
        } catch {
            result = .failure(error)
        }
        return Run(result: result, requests: await probe.requests, seeds: seeds.values)
    }

    private static func restFailure(_ code: Int = 500) -> Result<HTTPResponse, NetworkError> {
        let url = URL(string: "https://forum.hardware.fr/webservices/rest_api.php") ?? flagsURL
        return .failure(.httpStatus(code: code, url: url))
    }

    @Test("R335a-R335c: one GET of the captured URL each, redirects not followed, through a probe seeded with the account's cookies")
    func capturedRequests() async throws {
        let account = Self.account()
        let before = await account.cookies()
        let captures: [RESTFlagBucket: (file: String, id: String)] = [
            .participated: (RESTCapture.participated, "R335a"),
            .read: (RESTCapture.read, "R335b"),
            .favorites: (RESTCapture.favorites, "R335c")
        ]
        for bucket in RESTFlagBucket.allCases {
            let (file, id) = try #require(captures[bucket])
            let run = await Self.run(bucket, [.success(try RESTCapture.response(file, id: id))], account: account)
            let result = try run.result.get()
            #expect(result.source == .rest)
            #expect(result.value == (try RESTDocument.bucket(from: RESTCapture.data(file), bucket: bucket, postsPerPage: 40)))
            try #require(run.requests.count == 1)
            let request = try #require(run.requests.first)
            #expect(request.method == .get)
            #expect(request.url.absoluteString == (try Capture.meta(id)).url)
            #expect(request.redirectPolicy == .doNotFollow)
            #expect(request.body == nil)
            #expect(run.seeds.map(Set.init) == [Set(before)])
        }
        // Only read: the account keeps its cookies and gets no token.
        #expect(await account.cookies() == before)
        #expect(await account.hashCheck == nil)
    }

    @Test("The default probe keeps a loopback-only account's host policy, asserted without sending")
    func defaultProbeKeepsTheHostPolicy() async {
        let loopback = SessionHostPolicy.exactHost("127.0.0.1")
        let account = HFRSession(cookies: [], hashCheck: nil, now: Date(), configuration: .ephemeral, hosts: loopback)
        let probe = RESTFlagBucketClient(session: account).probe(cookies: []) as? HFRSession
        #expect(await probe?.hosts == loopback)
    }

    @Test("A failed REST answer falls back to the favourites page of the same owntopic, read with FavoritesParser")
    func fallbackToTheFavouritesPage() async throws {
        let cases: [RESTFlagBucket: (file: String, id: String)] = [
            .participated: ("R10-favourites-owntopic1", "R10"),
            .read: ("R603e-favourites-owntopic2", "R603e"),
            .favorites: ("R11-favourites-owntopic3-empty", "R11")
        ]
        for (bucket, capture) in cases {
            let (file, id) = capture
            let url = try #require(URL(string: try Capture.meta(id).url))
            let html = try Capture.response(file, url: url)
            let run = await Self.run(bucket, [Self.restFailure(), .success(html)])
            let result = try run.result.get()
            #expect(result.source == .html(.network(.httpStatus(
                code: 500, url: try #require(URL(string: "https://forum.hardware.fr/webservices/rest_api.php"))
            ))))
            #expect(result.value == (try FavoritesParser.parse(html.decodedText().text)))
            // `R11` is an account without favourite: the list body without a row.
            #expect(result.value.sections.isEmpty == (bucket == .favorites))
            try #require(run.requests.count == 2)
            // The captured URL of the page, not followed if redirected, never a topic page (E25).
            #expect(run.requests[1].url == url)
            #expect(run.requests[1].redirectPolicy == .doNotFollow)
        }
    }

    @Test("Every REST failure but the network's own ends falls back: not JSON, a checked field, a redirect")
    func fallbackReasons() async throws {
        let html = try Capture.response("R10-favourites-owntopic1", url: Self.flagsURL)
        let restURL = try #require(URL(string: try Capture.meta("R335a").url))
        let notJSON = HTTPResponse(statusCode: 200, url: restURL, body: Data("<html></html>".utf8))
        let flat = try RESTCapture.response(RESTCapture.participatedCategory, id: "R335e")
        let flatAsAnswer = HTTPResponse(statusCode: 200, url: restURL, body: flat.body)
        let redirect = HTTPResponse(statusCode: 302, headers: ["Location": "/"], url: restURL)
        let cases: [(HTTPResponse, RESTFallbackReason)] = [
            (notJSON, .response(.malformedDocument)),
            (flatAsAnswer, .response(.invalidValue(field: "resource.resources.page"))),
            (redirect, .network(.httpStatus(code: 302, url: restURL)))
        ]
        for (answer, reason) in cases {
            let run = await Self.run(.participated, [.success(answer), .success(html)])
            #expect(try run.result.get().source == .html(reason))
            #expect(run.requests.count == 2)
        }
    }

    @Test("Cancelled, offline or timed out: no fallback, nothing more sent")
    func noFallbackOnNetworkEnds() async {
        for error in [NetworkError.cancelled, .offline, .timedOut] {
            let run = await Self.run(.favorites, [.failure(error)])
            #expect(run.result == .failure(.network(error)))
            #expect(run.requests.count == 1)
        }
    }

    @Test("The fallback page served elsewhere or as an error is a failure, not a list")
    func fallbackFailures() async throws {
        let html = try Capture.response("R10-favourites-owntopic1", url: Self.flagsURL)
        let elsewhere = HTTPResponse(
            statusCode: 200, url: try #require(URL(string: "https://forum.hardware.fr/")), body: html.body
        )
        let moved = await Self.run(.participated, [Self.restFailure(), .success(elsewhere)])
        guard case .failure(.page(.malformed)) = moved.result else {
            Issue.record("a page served elsewhere was read: \(moved.result)")
            return
        }
        let down = await Self.run(.participated, [Self.restFailure(), .failure(.httpStatus(code: 503, url: Self.flagsURL))])
        #expect(down.result == .failure(.network(.httpStatus(code: 503, url: Self.flagsURL))))
    }

    @Test("HFR's stale-session page on the fallback (`R70b`) is `sessionExpired`; the account keeps its cookies")
    func staleSessionOnTheFallback() async throws {
        let account = Self.account()
        let stale = try Capture.response("R70b-favourites-owntopic1-stale-session", url: Self.flagsURL)
        let run = await Self.run(.participated, [Self.restFailure(), .success(stale)], account: account)
        #expect(run.result == .failure(.sessionExpired(.credentialsRefused)))
        #expect(await account.cookies().first { $0.name == "md_passs" }?.value == "somepass")
    }

    @Test("A logged-out favourites page (`R12`) comes back as its notice: the caller decides from its session")
    func loggedOutFallback() async throws {
        let page = try Capture.response("R12-favourites-anon", url: Self.flagsURL)
        let run = await Self.run(.participated, [Self.restFailure(), .success(page)])
        let value = try run.result.get().value
        #expect(value.sections.isEmpty)
        #expect(value.notice != nil)
    }

    @Test("A login adopted while the stale fallback answer was in flight gets no verdict from it: the page is read as is")
    func loginDuringTheFallback() async throws {
        let account = Self.account()
        let stale = try Capture.response("R70b-favourites-owntopic1-stale-session", url: Self.flagsURL)
        let login = [Self.cookie("md_user", "user2"), Self.cookie("md_passs", "loginpass"), Self.cookie("md_id", "900002")]
        let restURL = try #require(URL(string: try Capture.meta("R335a").url))
        let probe = MockTransport { request async throws(NetworkError) -> HTTPResponse in
            guard request.url == Self.flagsURL else { throw .httpStatus(code: 500, url: restURL) }
            try? await account.adoptLogin(cookies: login, hashCheck: "newhash", now: Date())
            return stale
        }
        let client = RESTFlagBucketClient(session: account, makeProbe: { _ in probe })
        let result = try await client.topics(in: .participated, postsPerPage: 40)
        #expect(result.value == (try FavoritesParser.parse(stale.decodedText().text)))
        #expect(await account.cookies().first { $0.name == "md_passs" }?.value == "loginpass")
    }

    @Test("A task cancelled before the call sends nothing")
    func cancelledBeforeTheCall() async {
        let probe = MockTransport(replies: [])
        let client = RESTFlagBucketClient(session: Self.account(), makeProbe: { _ in probe })
        let task = Task { () async throws -> RESTBrowsingResult<FavoritesPage> in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.topics(in: .favorites, postsPerPage: 40)
        }
        let failure: RESTBrowsingError? = switch await task.result {
        case .success: nil
        case .failure(let error): error as? RESTBrowsingError
        }
        #expect(failure == .network(.cancelled))
        #expect(await probe.requests.isEmpty)
    }

    @Test("A task cancelled while the REST answer comes back sends no HTML request")
    func cancelledBeforeTheFallback() async throws {
        let restURL = try #require(URL(string: try Capture.meta("R335a").url))
        let probe = MockTransport { _ async throws(NetworkError) -> HTTPResponse in
            withUnsafeCurrentTask { $0?.cancel() }
            throw .httpStatus(code: 500, url: restURL)
        }
        let client = RESTFlagBucketClient(session: Self.account(), makeProbe: { _ in probe })
        let task = Task { () async throws -> RESTBrowsingResult<FavoritesPage> in
            try await client.topics(in: .participated, postsPerPage: 40)
        }
        let failure: RESTBrowsingError? = switch await task.result {
        case .success: nil
        case .failure(let error): error as? RESTBrowsingError
        }
        #expect(failure == .network(.cancelled))
        #expect(await probe.requests.count == 1)
    }

    @Test("A posts-per-page below 1 is refused before any request")
    func invalidPageSize() async {
        let probe = MockTransport(replies: [])
        let client = RESTFlagBucketClient(session: Self.account(), makeProbe: { _ in probe })
        for size in [0, -40] {
            await #expect(throws: RESTBrowsingError.invalidTarget) { try await client.topics(in: .read, postsPerPage: size) }
        }
        #expect(await probe.requests.isEmpty)
    }
}
