import XCTest
@testable import HFRswift

final class FavoritesTopicListOrderingTests: XCTestCase {
    func testFlattenedTopicsSortsByMostRecentDateAcrossCategories() {
        let oldestTopic = makeTopic(title: "oldest", date: Date(timeIntervalSince1970: 1_000))
        let newestTopic = makeTopic(title: "newest", date: Date(timeIntervalSince1970: 3_000))
        let middleTopic = makeTopic(title: "middle", date: Date(timeIntervalSince1970: 2_000))

        let programming = makeFavorite(title: "Programmation", topics: [oldestTopic, middleTopic])
        let hardware = makeFavorite(title: "Hardware", topics: [newestTopic])

        let result = FavoritesTopicListOrdering.flattenedTopics(from: [programming, hardware])

        XCTAssertEqual(result.map { $0._aTitle ?? "" }, ["newest", "middle", "oldest"])
    }

    private func makeFavorite(title: String, topics: [Topic]) -> Favorite {
        let favorite = Favorite()
        let forum = Forum()
        forum.aTitle = title
        favorite.forum = forum
        favorite.topics = NSMutableArray(array: topics)
        return favorite
    }

    private func makeTopic(title: String, date: Date) -> Topic {
        let topic = Topic()
        topic._aTitle = title
        topic.dDateOfLastPost = date
        return topic
    }
}
