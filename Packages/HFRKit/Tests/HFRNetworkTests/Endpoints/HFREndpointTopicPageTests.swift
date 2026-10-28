import HFRModels
import Testing
@testable import HFRNetwork

struct HFREndpointTopicPageTests {
    private static let host = "https://forum.hardware.fr"

    @Test(arguments: [
        (CategoryID.forum(13), 1711, 450, "/forum2.php?config=hfr.inc&cat=13&post=1711&page=450"),
        (CategoryID.forum(10), 148745, 1, "/forum2.php?config=hfr.inc&cat=10&post=148745&page=1"),
        (CategoryID.forum(99), 5, 2, "/forum2.php?config=hfr.inc&cat=99&post=5&page=2"),
        (CategoryID.privateMessages, 8, 1, "/forum2.php?config=hfr.inc&cat=prive&post=8&page=1")
    ])
    func topicPage(category: CategoryID, post: Int, page: Int, expected: String) throws {
        let request = try HFREndpoint.topicPage(topic: TopicID(category: category, topic: post), page: page)
        #expect(request.url.absoluteString == Self.host + expected)
        #expect(request.method == .get)
        #expect(request.redirectPolicy == .follow)
    }

    @Test func pageDefaultsToOne() throws {
        let request = try HFREndpoint.topicPage(topic: TopicID(category: .forum(13), topic: 42))
        #expect(request.url.absoluteString == "\(Self.host)/forum2.php?config=hfr.inc&cat=13&post=42&page=1")
    }

    @Test("A message of unknown page is the R25 shape: page=1&numreponse=M, the same URL as the captured permalink request")
    func numreponse() throws {
        let topic = TopicID(category: .forum(13), topic: 28563)
        let request = try HFREndpoint.topicPage(topic: topic, page: 1, numreponse: 39971312)
        #expect(request.url.absoluteString == "\(Self.host)/forum2.php?config=hfr.inc&cat=13&post=28563&page=1&numreponse=39971312")
        #expect(request.redirectPolicy == .follow)
        let withAnchor = try HFREndpoint.topicPage(topic: topic, page: 1, anchor: 7, numreponse: 39971312)
        #expect(withAnchor.url.absoluteString.hasSuffix("&page=1&numreponse=39971312#t7"))
        let plain = try HFREndpoint.topicPage(topic: topic, page: 2)
        #expect(!plain.url.absoluteString.contains("numreponse"))
    }

    @Test func numreponseBelowOneIsRefused() {
        let topic = TopicID(category: .forum(13), topic: 42)
        #expect(throws: NetworkError.self) { try HFREndpoint.topicPage(topic: topic, numreponse: 0) }
        #expect(throws: NetworkError.self) { try HFREndpoint.topicPage(topic: topic, numreponse: -3) }
    }

    @Test func pageBelowOneIsRefused() {
        let topic = TopicID(category: .forum(13), topic: 42)
        #expect(throws: NetworkError.self) { try HFREndpoint.topicPage(topic: topic, page: 0) }
        #expect(throws: NetworkError.self) { try HFREndpoint.topicPage(topic: topic, page: -1) }
    }

    @Test func anchorBecomesFragment() throws {
        let topic = TopicID(category: .forum(13), topic: 42)
        let request = try HFREndpoint.topicPage(topic: topic, page: 2, anchor: 555)
        #expect(request.url.absoluteString == "\(Self.host)/forum2.php?config=hfr.inc&cat=13&post=42&page=2#t555")
    }

    @Test func postIDCarriesItsAnchor() throws {
        let post = PostID(topic: TopicID(category: .forum(13), topic: 42), numreponse: 1234)
        let request = try HFREndpoint.topicPage(post: post, page: 3)
        #expect(request.url.absoluteString == "\(Self.host)/forum2.php?config=hfr.inc&cat=13&post=42&page=3#t1234")
    }
}
