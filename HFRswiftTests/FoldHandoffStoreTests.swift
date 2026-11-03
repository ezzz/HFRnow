import XCTest
@testable import HFRswift

@MainActor
final class FoldHandoffStoreTests: XCTestCase {
    private let store = FoldHandoffStore.shared

    override func setUp() async throws {
        store.resetForTesting()
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

    func testReadingOfAnotherTabDoesNotReplaceSelectedTabReading() {
        let categoriesTopic = Topic()
        _ = store.register(tab: .categories, topic: categoriesTopic, page: 3, maxPage: 4)
        let favoritesToken = store.register(tab: .favorites, topic: Topic(), page: 1, maxPage: 1)
        store.update(token: favoritesToken, page: 1, maxPage: 2)

        let reading = store.beginRootSwap(selectedTab: .categories)

        XCTAssertTrue(reading?.topic === categoriesTopic)
        XCTAssertEqual(reading?.page, 3)
    }

    func testScheduledClearOnlyRemovesItsOwnTab() async {
        _ = store.register(tab: .categories, topic: Topic(), page: 5, maxPage: 5)
        let favoritesToken = store.register(tab: .favorites, topic: Topic(), page: 2, maxPage: 2)

        await store.scheduleClear(token: favoritesToken, after: .milliseconds(10)).value

        XCTAssertNil(store.readings[.favorites])
        XCTAssertEqual(store.readings[.categories]?.page, 5)
    }

    func testRootSwapDropsReadingsOfOtherTabs() {
        _ = store.register(tab: .favorites, topic: Topic(), page: 2, maxPage: 2)

        XCTAssertNil(store.beginRootSwap(selectedTab: .categories))
        XCTAssertNil(store.beginRootSwap(selectedTab: .favorites))
    }

    func testStaleTokenDoesNotOverwriteNewerReading() {
        let oldToken = store.register(tab: .categories, topic: Topic(), page: 1, maxPage: 1)
        _ = store.register(tab: .categories, topic: Topic(), page: 7, maxPage: 9)

        store.update(token: oldToken, page: 2, maxPage: 2)

        XCTAssertEqual(store.beginRootSwap(selectedTab: .categories)?.page, 7)
    }

    func testScheduledClearRemovesReadingWithoutRootSwap() async {
        let token = store.register(tab: .favorites, topic: Topic(), page: 2, maxPage: 2)

        await store.scheduleClear(token: token, after: .milliseconds(10)).value

        XCTAssertNil(store.beginRootSwap(selectedTab: .favorites))
    }

    func testScheduledClearIsCancelledByRootSwap() async {
        let token = store.register(tab: .favorites, topic: Topic(), page: 2, maxPage: 2)
        let clear = store.scheduleClear(token: token, after: .milliseconds(10))
        let reading = store.beginRootSwap(selectedTab: .favorites)

        await clear.value

        XCTAssertEqual(reading?.page, 2)
        XCTAssertNotNil(store.beginRootSwap(selectedTab: .favorites))
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
