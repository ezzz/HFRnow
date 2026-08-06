import XCTest
@testable import HFRswift

@MainActor
final class TopicNavigationIdentityTests: XCTestCase {
    func testIdentitySurvivesTopicObjectReplacement() {
        let original = Topic()
        original.postID = 29332
        original.catID = 13

        let refreshed = Topic()
        refreshed.postID = 29332
        refreshed.catID = 13

        XCTAssertEqual(
            TopicNavigationIdentity.id(for: original, context: .favorites),
            TopicNavigationIdentity.id(for: refreshed, context: .favorites)
        )
    }

    func testIdentityIgnoresPageAndAnchorForQueryURL() {
        let firstPage = Topic()
        firstPage.aURL = "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=29332&page=1&p=1#t100"

        let laterPage = Topic()
        laterPage.aURL = "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=29332&page=344&p=2#t999"

        XCTAssertEqual(
            TopicNavigationIdentity.id(for: firstPage, context: .forum(selectedFlag: .all)),
            TopicNavigationIdentity.id(for: laterPage, context: .forum(selectedFlag: .all))
        )
    }

    func testIdentityReadsPostIDFromSEOURL() {
        let firstPage = Topic()
        firstPage.aURL = "https://forum.hardware.fr/hfr/gsmgpspda/android/redface-client-android-sujet_29332_1.htm#t100"

        let laterPage = Topic()
        laterPage.aURL = "https://forum.hardware.fr/hfr/gsmgpspda/android/redface-client-android-sujet_29332_344.htm#t999"

        XCTAssertEqual(
            TopicNavigationIdentity.id(for: firstPage, context: .favorites),
            TopicNavigationIdentity.id(for: laterPage, context: .favorites)
        )
    }

    func testPrivateMessageIdentityUsesSeparateNamespace() {
        let topic = Topic()
        topic.postID = 29332
        topic.catID = 13

        XCTAssertNotEqual(
            TopicNavigationIdentity.id(for: topic, context: .favorites),
            TopicNavigationIdentity.id(for: topic, context: .privateMessages)
        )
    }

    func testCanonicalURLFallbackIgnoresPaginationParameters() {
        let firstPage = Topic()
        firstPage.aURL = "https://example.com/topic?view=thread&page=1&p=1#top"

        let laterPage = Topic()
        laterPage.aURL = "https://example.com/topic?p=2&page=8&view=thread#bottom"

        XCTAssertEqual(
            TopicNavigationIdentity.id(for: firstPage, context: .generic),
            TopicNavigationIdentity.id(for: laterPage, context: .generic)
        )
    }
}
