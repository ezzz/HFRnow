import Foundation
import HFRModels
import Testing
@testable import HFRNetwork

/// #1394: once HFR has served a page of a topic at its canonical path, another page of that topic is asked for at that path
/// with the page number changed (legacy `TopicPageURLRouting.replacingPage`, `HFRswift/Swift/Common.swift:2818-2834` @ 87fe0d1c),
/// instead of `forum2.php`, which HFR answers with one or two 301 hops first (R5, `R24`, `R298a`).
struct HFREndpointServedTopicPageTests {
    private static let host = "https://forum.hardware.fr"
    private static let apple = TopicID(category: .forum(25), topic: 1711)
    private static let pizza = TopicID(category: .forum(13), topic: 28563)

    private static func url(_ text: String) throws -> URL { try #require(URL(string: text)) }

    @Test("A page served at its canonical path gives the other pages' path (R298a final URL)")
    func canonicalWithoutSubCategory() throws {
        let served = try Self.url("\(Self.host)/hfr/apple/unique-forum-released-sujet_1711_1.htm")
        let request = try HFREndpoint.topicPage(topic: Self.apple, page: 3, servedAt: served)
        #expect(request.url.absoluteString == "\(Self.host)/hfr/apple/unique-forum-released-sujet_1711_3.htm")
        #expect(request.method == .get)
        #expect(request.redirectPolicy == .follow)
        #expect(request.timeout == RequestTimeout.standard)
    }

    @Test("The sub-category segment and a fragment of the served URL: segment kept, fragment dropped (R24 final URL)")
    func canonicalWithSubCategory() throws {
        let served = try Self.url("\(Self.host)/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t5")
        let request = try HFREndpoint.topicPage(topic: Self.pizza, page: 2202, servedAt: served)
        // Past the end HFR answers this very path with a 302 to the last page (`R24`'s third hop).
        #expect(request.url.absoluteString == "\(Self.host)/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2202.htm")
    }

    @Test(
        "Anything but a canonical page of the same topic on the forum origin falls back to forum2.php",
        arguments: [
            "https://forum.hardware.fr/hfr/apple/unique-forum-released-sujet_1712_1.htm",  // another topic
            "http://forum.hardware.fr/hfr/apple/unique-forum-released-sujet_1711_1.htm",  // not https
            "https://forum.hardware.fr:8443/hfr/apple/unique-forum-released-sujet_1711_1.htm",  // explicit port
            "https://user@forum.hardware.fr/hfr/apple/unique-forum-released-sujet_1711_1.htm",  // user info
            "https://example.com/hfr/apple/unique-forum-released-sujet_1711_1.htm",  // another host
            "https://forum-images.hardware.fr/hfr/apple/unique-forum-released-sujet_1711_1.htm",  // another forum host
            "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=25&post=1711&page=1",  // id form
            "https://forum.hardware.fr/hfr/apple/x/y/unique-sujet_1711_1.htm",  // not the R5 shape
            "https://forum.hardware.fr/hfr/reseauxpersosoho/FAI/sujet_1711_1.htm",  // empty slug: not a captured final URL
            "https://forum.hardware.fr/x/apple/unique-forum-released-sujet_1711_1.htm"  // not under /hfr/
        ]
    )
    func fallsBack(served text: String) throws {
        let request = try HFREndpoint.topicPage(topic: Self.apple, page: 2, servedAt: try Self.url(text))
        #expect(request.url.absoluteString == "\(Self.host)/forum2.php?config=hfr.inc&cat=25&post=1711&page=2")
    }

    @Test("No served page: forum2.php, as before")
    func noServedPage() throws {
        let request = try HFREndpoint.topicPage(topic: Self.apple, page: 2, servedAt: nil)
        #expect(request.url.absoluteString == "\(Self.host)/forum2.php?config=hfr.inc&cat=25&post=1711&page=2")
    }

    @Test("A private conversation always goes through forum2.php: HFR serves it there, in place (R388a)")
    func privateConversation() throws {
        let conversation = TopicID(category: .privateMessages, topic: 1711)
        let served = try Self.url("\(Self.host)/hfr/apple/unique-forum-released-sujet_1711_1.htm")
        let request = try HFREndpoint.topicPage(topic: conversation, page: 2, servedAt: served)
        #expect(request.url.absoluteString == "\(Self.host)/forum2.php?config=hfr.inc&cat=prive&post=1711&page=2")
    }

    @Test("A page below 1 is refused, whatever the served page")
    func invalidPage() throws {
        let served = try Self.url("\(Self.host)/hfr/apple/unique-forum-released-sujet_1711_1.htm")
        #expect(throws: NetworkError.self) { try HFREndpoint.topicPage(topic: Self.apple, page: 0, servedAt: served) }
    }
}
