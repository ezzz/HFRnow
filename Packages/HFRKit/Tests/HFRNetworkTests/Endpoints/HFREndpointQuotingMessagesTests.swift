import HFRModels
import Testing
@testable import HFRNetwork

/// #1039: the quote view of one message, requested in the shape of capture `R126a` (HFR-PROTOCOL §6c « Batch A »).
struct HFREndpointQuotingMessagesTests {
    private static let host = "https://forum.hardware.fr"

    /// `R126a` byte for byte (`url_template` with its numbers): the empty parameters stay, in HFR's order.
    @Test func theRequestIsTheCapturedShape() throws {
        let topic = TopicID(category: .forum(13), topic: 28563)
        let request = try HFREndpoint.quotingMessages(topic: topic, subcategory: 433, numreponse: 35_643_367)
        #expect(request.url.absoluteString == Self.host + "/forum2.php?config=hfr.inc&cat=13&subcat=433&post=28563&page=1&p=1&sondage="
            + "&owntopic=&trash=&trash_post=&print=&numreponse=35643367&quote_only=1&new=0&nojs=0")
        #expect(request.method == .get)
        #expect(request.redirectPolicy == .follow)
    }

    /// HFR writes an empty `subcat=` for a forum without sub-categories (the other empties of the link are written that way).
    @Test func aMissingSubcategoryIsWrittenEmpty() throws {
        let request = try HFREndpoint.quotingMessages(topic: TopicID(category: .forum(13), topic: 5), subcategory: nil, numreponse: 9)
        #expect(request.url.absoluteString.contains("&cat=13&subcat=&post=5&page=1&"))
    }

    @Test func aMessageNumberBelowOneIsRefused() {
        #expect(throws: NetworkError.self) {
            try HFREndpoint.quotingMessages(topic: TopicID(category: .forum(13), topic: 5), subcategory: nil, numreponse: 0)
        }
    }
}
