import Foundation
import HFRModels
import HFRNetwork
import Testing
@testable import HFRClient

/// The intra-topic search flow over the captured answers: `R52a` (302 to the match) and `R52b` (no match).
@Suite("Topic search (LOT-046)")
struct TopicSearchFlowTests {
    static let cuisine = TopicID(category: .forum(13), topic: 28563)
    static let query = TopicSearchQuery(topic: cuisine, word: "napolitaine", formPage: "1")

    private static func run(
        _ query: TopicSearchQuery = query, token: String? = "REDACTED", replies: [Result<HTTPResponse, NetworkError>]
    ) async -> (result: Result<TopicSearchResult, TopicSearchError>, requests: [HTTPRequest]) {
        let session = ScriptedFlagSession(replies, hashCheck: token)
        let result: Result<TopicSearchResult, TopicSearchError>
        do {
            result = .success(try await TopicSearchFlow().search(query, through: session))
        } catch {
            result = .failure(error)
        }
        return (result, await session.requests)
    }

    /// `R52a` as HFR answered it: 302 and its `Location`, no body.
    static func redirect(to location: String) throws -> HTTPResponse {
        let meta = try Capture.meta("R52a")
        let url = try #require(URL(string: meta.url))
        return HTTPResponse(statusCode: 302, headers: ["Location": location], url: url)
    }

    static func capturedLocation() throws -> String {
        try #require(try Capture.meta("R52a").redirects?.first?.location)
    }

    /// `R52a` answered the browser's field set (`config`, `sondage`, `owntopic`, `dep=0`, `firstnum`, no `filter`); the flow sends
    /// LOT-041's legacy body, whose answer is not captured (LOT-046 spec, pending capture). Only `R52a`'s status and
    /// `Location` are used here.
    @Test("R52a: the match is the Location, resolved on the forum; one POST, redirects not followed")
    func match() async throws {
        let location = try Self.capturedLocation()
        let (result, requests) = await Self.run(replies: [.success(try Self.redirect(to: location))])
        let expected = try #require(URL(string: "https://forum.hardware.fr" + location))
        #expect(result == .success(.match(expected)))
        #expect(requests.count == 1)
        let post = try #require(requests.first)
        #expect(post.method == .post)
        #expect(post.url.absoluteString == (try Capture.meta("R52a")).url)
        #expect(post.redirectPolicy == .doNotFollow)
        let body = try #require(SearchCapture.body(of: post))
        #expect(body.hasPrefix("hash_check=REDACTED&"))
        #expect(body.contains("&post=28563&cat=13&word=napolitaine&"))
    }

    @Test("R52b: HFR's sentence is 'no match'")
    func noMatch() async throws {
        let page = try SearchCapture.answer("R52b-transsearch-no-match", id: "R52b")
        let (result, requests) = await Self.run(replies: [.success(page)])
        #expect(result == .success(.noMatch))
        #expect(requests.count == 1)
    }

    @Test(
        "A Location off the forum or off the searched topic is refused",
        arguments: [
            "https://example.com/forum2.php?post=28563&cat=13&page=1#t2666649",
            "http://forum.hardware.fr/forum2.php?post=28563&cat=13&page=1#t2666649",
            "https://forum.hardware.fr:8443/forum2.php?post=28563&cat=13&page=1#t2666649",
            "/forum2.php?post=28564&cat=13&page=1#t2666649",
            "/forum2.php?post=28563&cat=5&page=1#t2666649",
            "/forum2.php?post=28563&cat=prive&page=1#t2666649",
            "/forum1.php?post=28563&cat=13&page=1",
            "/forum2.php?cat=13&page=1"
        ]
    )
    func invalidLocation(location: String) async throws {
        let (result, _) = await Self.run(replies: [.success(try Self.redirect(to: location))])
        let resolved = try #require(URL(string: location, relativeTo: URL(string: try Capture.meta("R52a").url))?.absoluteURL)
        #expect(result == .failure(.invalidLocation(resolved)))
    }

    @Test("A redirect without Location is not an answer")
    func redirectWithoutLocation() async throws {
        var moved = try Self.redirect(to: "")
        moved.headers["Location"] = nil
        let (result, _) = await Self.run(replies: [.success(moved)])
        #expect(result == .failure(.unrecognizedAnswer(message: nil)))
    }

    /// Other captured pages, used only to check that nothing but HFR's sentence reads as "no match"; they are not claims
    /// about what `transsearch.php` answers (not captured).
    @Test("Only HFR's no-match sentence is 'no match': a refusal, a logged-out page or another page is reported")
    func otherPagesAreNotNoMatch() async throws {
        let badToken = await Self.run(replies: [.success(try Capture.response("W17b-mp-reply-bad-token-rejected"))])
        guard case .failure(.rejected(let message?)) = badToken.result else {
            Issue.record("W17b: \(badToken.result)")
            return
        }
        #expect(message.hasPrefix("Une erreur est survenue lors de l'envoi des données"))
        let loggedOut = await Self.run(replies: [.success(try Capture.response("W17c-mp-reply-logged-out-rejected"))])
        guard case .failure(.notLoggedIn) = loggedOut.result else {
            Issue.record("W17c: \(loggedOut.result)")
            return
        }
        let topicPage = await Self.run(replies: [.success(try Capture.response("R21-topic-p1-logged-in"))])
        #expect(topicPage.result == .failure(.unrecognizedAnswer(message: nil)))
    }

    @Test("No token or no criterion fails before sending")
    func refusedBeforeSending() async throws {
        let noToken = await Self.run(token: nil, replies: [])
        #expect(noToken.result == .failure(.missingToken))
        #expect(noToken.requests.isEmpty)
        let nothing = await Self.run(TopicSearchQuery(topic: Self.cuisine, word: " ", author: ""), replies: [])
        #expect(nothing.result == .failure(.network(.invalidRequest(reason: "no search criterion"))))
        #expect(nothing.requests.isEmpty)
    }

    @Test("A failure is reported once, the POST never retried", arguments: [NetworkError.timedOut, .offline])
    func transportFailure(failure: NetworkError) async throws {
        let (result, requests) = await Self.run(replies: [.failure(failure), .success(try Self.redirect(to: "/"))])
        #expect(result == .failure(.network(failure)))
        #expect(requests.count == 1)
    }

    @Test("An HTTP error status is a network failure")
    func httpError() async throws {
        let url = try #require(URL(string: try Capture.meta("R52a").url))
        let (result, _) = await Self.run(replies: [.success(HTTPResponse(statusCode: 500, url: url))])
        #expect(result == .failure(.network(.httpStatus(code: 500, url: url))))
    }

    @Test("A cancelled task sends nothing")
    func cancelledBeforeSending() async throws {
        let session = ScriptedFlagSession([.success(try Self.redirect(to: try Self.capturedLocation()))], hashCheck: "REDACTED")
        let task = Task { () async -> TopicSearchError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do throws(TopicSearchError) {
                _ = try await TopicSearchFlow().search(Self.query, through: session)
                return nil
            } catch {
                return error
            }
        }
        #expect(await task.value == .network(.cancelled))
        #expect(await session.requests.isEmpty)
    }
}
