import XCTest
@testable import HFRswift

final class TopicQuickActionPolicyTests: XCTestCase {
    func testFavoritesLastReplyPrefersLastPageOverFlaggedCurrentURL() {
        let topic = Topic()
        topic.aURL = "/forum2.php?config=hfr.inc&cat=13&post=42&page=3#t123"
        topic.aURLOfLastPost = "/forum2.php?config=hfr.inc&cat=13&post=42&page=9#t999"
        topic.aURLOfLastPage = "/forum2.php?config=hfr.inc&cat=13&post=42&page=9"

        let result = TopicQuickActionPolicy.lastReplyURL(for: topic, context: .favorites)

        XCTAssertEqual(result, "/forum2.php?config=hfr.inc&cat=13&post=42&page=9")
    }

    func testForumLastReplyStillPrefersLastPostAnchor() {
        let topic = Topic()
        topic.aURL = "/forum2.php?config=hfr.inc&cat=13&post=42&page=3#t123"
        topic.aURLOfLastPost = "/forum2.php?config=hfr.inc&cat=13&post=42&page=9#t999"
        topic.aURLOfLastPage = "/forum2.php?config=hfr.inc&cat=13&post=42&page=9"

        let result = TopicQuickActionPolicy.lastReplyURL(for: topic, context: .forum(selectedFlag: .all))

        XCTAssertEqual(result, "/forum2.php?config=hfr.inc&cat=13&post=42&page=9#t999")
    }
}
