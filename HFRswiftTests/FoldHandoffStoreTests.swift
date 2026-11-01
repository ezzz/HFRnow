import XCTest
@testable import HFRswift

@MainActor
final class FoldHandoffStoreTests: XCTestCase {
    private let store = FoldHandoffStore.shared

    override func setUp() async throws {
        // Reset shared state: a swap drops any pending push, consuming clears it.
        _ = store.beginRootSwap(selectedTab: .categories)
        _ = store.consumePendingPush(for: .categories)
    }

    func testRootSwapReplaysReadingOfSelectedTabOnLatestPage() {
        let topic = Topic()
        topic.postID = 4242
        let token = store.register(tab: .favorites, topic: topic, page: 1, maxPage: 5)
        store.update(token: token, page: 3, maxPage: 6)

        let reading = store.beginRootSwap(selectedTab: .favorites)

        XCTAssertEqual(reading?.page, 3)
        XCTAssertEqual(reading?.maxPage, 6)
        XCTAssertTrue(reading?.topic === topic)
        XCTAssertEqual(reading?.navigationTarget.page, 3)
    }

    func testRootSwapIgnoresReadingOfAnotherTab() {
        _ = store.register(tab: .messages, topic: Topic(), page: 2, maxPage: 2)

        XCTAssertNil(store.beginRootSwap(selectedTab: .categories))
    }

    func testStaleTokenDoesNotOverwriteNewerReading() {
        let oldToken = store.register(tab: .categories, topic: Topic(), page: 1, maxPage: 1)
        _ = store.register(tab: .categories, topic: Topic(), page: 7, maxPage: 9)

        store.update(token: oldToken, page: 2, maxPage: 2)

        XCTAssertEqual(store.beginRootSwap(selectedTab: .categories)?.page, 7)
    }

    func testPendingPushIsConsumedOnceByItsTab() {
        let target = TopicNavigationTarget(
            topic: Topic(),
            page: 4,
            maxPage: 4,
            openedURL: nil,
            initialScroll: nil,
            context: .generic
        )
        store.requestCompactPush(tab: .favorites, target: target)

        XCTAssertNil(store.consumePendingPush(for: .messages))
        XCTAssertEqual(store.consumePendingPush(for: .favorites)?.page, 4)
        XCTAssertNil(store.consumePendingPush(for: .favorites))
    }
}
