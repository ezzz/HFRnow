import Foundation
import HFRModels
@testable import HFRNetwork
import HFRParsing
import Testing
@testable import HFRClient

/// LOT-058: marking a private conversation unread. The link comes from the conversation page (`RA1`-`RA4`), the answer
/// is `W18`, and the MP list afterwards (`R13b`) shows the conversation unread.
@Suite("Mark a private conversation unread")
struct MarkUnreadTests {
    private static let conversation = TopicID(category: .privateMessages, topic: 3207033)
    private static let sentence = "Le message a été marqué comme non lu avec succès"

    private static func run(link: URL, reply: Result<HTTPResponse, NetworkError>?) async
        -> (result: Result<TopicFlagResult, TopicFlagError>, requests: [HTTPRequest]) {
        let session = ScriptedFlagSession(reply.map { [$0] } ?? [])
        let result: Result<TopicFlagResult, TopicFlagError>
        do {
            result = .success(try await TopicFlagFlow().follow(.markUnread, link: link, through: session))
        } catch {
            result = .failure(error)
        }
        return (result, await session.requests)
    }

    /// The conversation page's own link, read by the metadata parser.
    private static func pageLink(_ file: String) throws -> URL {
        let html = try Capture.page(file)
        let metadata = try TopicPageMetadataParser.parse(html: html, pageURL: "/forum2.php?config=hfr.inc&cat=prive&post=3207033&page=1")
        return try #require(metadata.markUnreadURL)
    }

    @Test("RA1's link is the one W18 requested; W18 confirms it after one GET, redirects not followed")
    func confirmed() async throws {
        let link = try Self.pageLink("RA1-mp-thread-after-create")
        #expect(link == (try FlagCapture.requestURL("W18")))
        let (result, requests) = await Self.run(link: link, reply: try FlagCapture.page("W18"))
        let mark = try result.get()
        #expect(mark.action == .markUnread)
        #expect(mark.topic == Self.conversation)
        #expect(mark.message == Self.sentence)
        #expect(mark.refreshURL.path() == "/forum1.php")
        #expect(requests.count == 1)
        #expect(requests.first?.method == .get)
        #expect(requests.first?.url == link)
        #expect(requests.first?.redirectPolicy == .doNotFollow)
        #expect(requests.first?.body == nil)
    }

    @Test("R13b, the MP list after W18, shows the conversation unread")
    func listAfterward() throws {
        let list = try Capture.page("R13b-mp-list-after-mark-unread")
        let page = try PrivateMessageListParser.parse(list, pageURL: "/forum1.php?config=hfr.inc&cat=prive&page=1")
        let thread = try #require(page.threads.first { $0.summary.topicID == Self.conversation })
        #expect(thread.isUnread)
    }

    @Test("Another write's confirmation, a refusal or a logged-out answer is never a mark", arguments: [
        ("P03a", TopicFlagError.unconfirmed(.unexpectedConfirmation(message: "Favori positionné avec succès"))),
        ("P03d", .unconfirmed(.unexpectedConfirmation(message: "Drapeau effacé avec succès"))),
        ("W15", .unconfirmed(.unexpectedConfirmation(message: "Votre message a été édité avec succès !")))
    ])
    func otherAnswers(answer: String, expected: TopicFlagError) async throws {
        let (result, requests) = await Self.run(link: try FlagCapture.requestURL("W18"), reply: try FlagCapture.page(answer))
        #expect(result == .failure(expected))
        #expect(requests.count == 1)
    }

    @Test("A refusal, a logged-out page and a failure after sending are reported, never retried", arguments: [
        "W17b", "W17c", "transport"
    ])
    func failures(answer: String) async throws {
        let reply: Result<HTTPResponse, NetworkError> = answer == "transport" ? .failure(.timedOut) : try FlagCapture.page(answer)
        let (result, requests) = await Self.run(link: try FlagCapture.requestURL("W18"), reply: reply)
        switch (answer, result) {
        case ("W17b", .failure(.rejected)), ("W17c", .failure(.notLoggedIn)), ("transport", .failure(.unconfirmed(.transport))):
            break
        default:
            Issue.record("\(answer): unexpected \(result)")
        }
        #expect(requests.count == 1)
    }

    @Test("Only a forum-origin nonlu.php link of a private conversation is followed", arguments: [
        "https://forum.hardware.fr/user/nonlu.php?config=hfr.inc&cat=13&subcat=0&post=28563&page=1",
        "https://example.org/user/nonlu.php?config=hfr.inc&cat=prive&post=3207033",
        "http://forum.hardware.fr/user/nonlu.php?config=hfr.inc&cat=prive&post=3207033",
        "https://forum.hardware.fr:8443/user/nonlu.php?config=hfr.inc&cat=prive&post=3207033",
        "https://forum.hardware.fr/user/addflag.php?config=hfr.inc&cat=prive&post=3207033",
        "https://forum.hardware.fr/user/nonlu.php?config=hfr.inc&cat=prive&post=3207033&cat=13",
        "https://forum.hardware.fr/user/nonlu.php?config=hfr.inc&cat=prive&post=0",
        "https://forum.hardware.fr/user/nonlu.php?cat=prive&post=3207033"
    ])
    func refusedLinks(raw: String) async throws {
        let (result, requests) = await Self.run(link: try #require(URL(string: raw)), reply: nil)
        #expect(result == .failure(.invalidLink))
        #expect(requests.isEmpty)
    }

    @Test("The flag writes still refuse a private conversation's links")
    func flagsStayOnForumTopics() throws {
        let link = try FlagCapture.requestURL("W18")
        #expect(FlagLink(link, path: "/user/nonlu.php", privateThread: true)?.topic == Self.conversation)
        #expect(FlagLink(link, path: "/user/nonlu.php") == nil)
        let addflag = try FlagCapture.requestURL("P03a")
        #expect(FlagLink(addflag, path: "/user/addflag.php", privateThread: true) == nil)
    }

    @Test("The public entry point checks the session first: a session that never logged in sends nothing")
    func gated() async throws {
        let session = HFRSession(
            cookies: [], hashCheck: "token", now: Date(), configuration: .ephemeral, hosts: .exactHost("127.0.0.1")
        )
        let link = try FlagCapture.requestURL("W18")
        await #expect(throws: TopicFlagError.sessionNotConfirmed(.expired(.noIdentityCookie))) {
            try await TopicFlagFlow().markUnread(link: link, in: session)
        }
    }
}
