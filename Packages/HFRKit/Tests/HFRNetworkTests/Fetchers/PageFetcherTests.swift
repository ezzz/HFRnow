import Foundation
import HFRModels
import Testing
@testable import HFRNetwork

struct PageFetcherTests {
    private struct Rig {
        let fetcher: PageFetcher
        let session: MockTransport
        let anonymous: MockTransport
    }

    private func makeRig(
        session: [Result<HTTPResponse, NetworkError>] = [], anonymous: [Result<HTTPResponse, NetworkError>] = []
    ) -> Rig {
        let sessionMock = MockTransport(replies: session)
        let anonymousMock = MockTransport(replies: anonymous)
        return Rig(fetcher: PageFetcher(session: sessionMock, anonymous: anonymousMock), session: sessionMock, anonymous: anonymousMock)
    }

    @Test func listsGoThroughTheSessionByDefaultWithTheEndpointRequest() async throws {
        let reply = Result<HTTPResponse, NetworkError>.success(okResponse(body: "<html>é</html>"))
        let rig = makeRig(session: Array(repeating: reply, count: 6))
        let (fetcher, session, anonymous) = (rig.fetcher, rig.session, rig.anonymous)
        _ = try await fetcher.home()
        _ = try await fetcher.topicList(category: .forum(13), page: 2)
        _ = try await fetcher.favorites()
        _ = try await fetcher.privateMessages()
        _ = try await fetcher.profile(memberID: 42)
        _ = try await fetcher.smileySearch("smile")
        let expected = try [
            HFREndpoint.home(), HFREndpoint.topicList(category: .forum(13), page: 2), HFREndpoint.favorites(),
            HFREndpoint.privateMessages(), HFREndpoint.publicProfile(memberID: 42), HFREndpoint.smileySearch("smile")
        ]
        #expect(await session.requests == expected)
        #expect(await anonymous.requests.isEmpty)
    }

    @Test func topicPageIsAnonymousByDefaultAndAuthenticatedOnRequest() async throws {
        let reply = Result<HTTPResponse, NetworkError>.success(okResponse("/hfr/Discussions/x-sujet_5_2.htm"))
        let rig = makeRig(session: [reply], anonymous: [reply])
        let (fetcher, session, anonymous) = (rig.fetcher, rig.session, rig.anonymous)
        let topic = TopicID(category: .forum(13), topic: 5)
        _ = try await fetcher.topicPage(topic: topic, page: 2)
        #expect(await session.requests.isEmpty)
        #expect(await anonymous.requests == [try HFREndpoint.topicPage(topic: topic, page: 2)])
        _ = try await fetcher.topicPage(topic: topic, page: 2, as: .authenticated)
        #expect(await session.requests.count == 1)
        #expect(await anonymous.requests.count == 1)
    }

    @Test func rawPageCarriesTextCharsetURLAndStatus() async throws {
        let latin1 = HTTPResponse(
            statusCode: 200, headers: ["Content-Type": "text/html; charset=ISO-8859-1"],
            url: URL(string: "https://forum.hardware.fr/final") ?? URL(fileURLWithPath: "/"), body: Data([0x63, 0x61, 0x66, 0xE9])
        )
        let meta = okResponse(body: "<meta charset=\"utf-8\">é", contentType: "text/html")
        let none = okResponse(body: "plain", contentType: "text/html")
        let fetcher = makeRig(session: [.success(latin1), .success(meta), .success(none)]).fetcher
        let first = try await fetcher.home()
        #expect(first.text == "café")
        #expect(first.encoding == .windows1252)
        #expect(first.declaredCharset == "iso-8859-1")
        #expect(first.finalURL.path == "/final")
        #expect(first.statusCode == 200)
        let second = try await fetcher.home()
        #expect(second.declaredCharset == "utf-8")
        #expect(second.text.hasSuffix("é"))
        #expect(try await fetcher.home().declaredCharset == nil)
    }

    @Test func httpErrorAndInvalidInputAreThrownWithoutSending() async throws {
        let url = try #require(URL(string: "https://forum.hardware.fr/"))
        let rig = makeRig(session: [.success(HTTPResponse(statusCode: 503, url: url))])
        let (fetcher, session) = (rig.fetcher, rig.session)
        await #expect(throws: NetworkError.httpStatus(code: 503, url: url)) { try await fetcher.home() }
        await #expect(throws: NetworkError.self) { try await fetcher.topicList(category: .forum(13), page: 0) }
        await #expect(throws: NetworkError.self) { try await fetcher.topicList(category: .privateMessages) }
        await #expect(throws: NetworkError.self) { try await fetcher.smileySearch("ab") }
        #expect(await session.requests.count == 1)
    }

    @Test func aTaskCancelledBeforeStartingSendsNothing() async {
        let rig = makeRig()
        let (fetcher, session, anonymous) = (rig.fetcher, rig.session, rig.anonymous)
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await fetcher.topicPage(topic: TopicID(category: .forum(13), topic: 5))
        }
        task.cancel()
        await #expect(throws: NetworkError.cancelled) { try await task.value }
        #expect(await session.requests.isEmpty)
        #expect(await anonymous.requests.isEmpty)
    }

    @Test func locationIsReadFromCanonicalURLs() throws {
        func location(_ path: String) -> TopicPageLocation? {
            URL(string: "https://forum.hardware.fr" + path).flatMap(TopicPageLocation.init(url:))
        }
        #expect(location("/hfr/Programmation/Divers-6/hfr-android-sujet_148745_1.htm") == TopicPageLocation(topic: 148_745, page: 1))
        #expect(location("/hfr/Discussions/x-sujet_5_12.htm") == TopicPageLocation(topic: 5, page: 12))
        #expect(location("/forum2.php") == nil)
        #expect(location("/hfr/Discussions/x-sujet_5_0.htm") == nil)
        #expect(location("/hfr/Discussions/x_5_2.htm") == nil)
        #expect(location("/hfr/Discussions/notsujet_5_2.htm") == nil)
        #expect(location("/hfr/Discussions/sujet_5_2.htm") == TopicPageLocation(topic: 5, page: 2))
    }
}
