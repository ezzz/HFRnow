import XCTest
@testable import HFRswift

final class FavoritesViewModelTests: XCTestCase {
    func testRemoveTopicRemovesMatchingTopicAndKeepsEmptySections() {
        let favoriteA = makeFavorite(sectionTitle: "A", topicIDs: [11, 12])
        let favoriteB = makeFavorite(sectionTitle: "B", topicIDs: [12])
        let viewModel = FavoritesViewModel(
            favoritesLoader: FavoritesLoaderStub(),
            initialFavorites: [favoriteA, favoriteB]
        )

        viewModel.removeTopic(withPostID: 12)

        XCTAssertEqual(viewModel.favorites.count, 2)
        let remainingTopics = (viewModel.favorites.first?.topics as? [Topic]) ?? []
        XCTAssertEqual(remainingTopics.map { Int($0.postID) }, [11])
        let emptyTopics = (viewModel.favorites.last?.topics as? [Topic]) ?? []
        XCTAssertTrue(emptyTopics.isEmpty)
    }

    func testRemoveTopicWithUnknownPostIDKeepsFavoritesUnchanged() {
        let favorite = makeFavorite(sectionTitle: "A", topicIDs: [11, 12])
        let viewModel = FavoritesViewModel(
            favoritesLoader: FavoritesLoaderStub(),
            initialFavorites: [favorite]
        )

        viewModel.removeTopic(withPostID: 99)

        XCTAssertEqual(viewModel.favorites.count, 1)
        let topics = (viewModel.favorites.first?.topics as? [Topic]) ?? []
        XCTAssertEqual(topics.map { Int($0.postID) }, [11, 12])
    }

    func testRemoveTopicWithInvalidPostIDDoesNothing() {
        let favorite = makeFavorite(sectionTitle: "A", topicIDs: [11])
        let viewModel = FavoritesViewModel(
            favoritesLoader: FavoritesLoaderStub(),
            initialFavorites: [favorite]
        )

        viewModel.removeTopic(withPostID: 0)

        XCTAssertEqual(viewModel.favorites.count, 1)
        let topics = (viewModel.favorites.first?.topics as? [Topic]) ?? []
        XCTAssertEqual(topics.map { Int($0.postID) }, [11])
    }

    private func makeFavorite(sectionTitle: String, topicIDs: [Int]) -> Favorite {
        let favorite = Favorite()
        let forum = Forum()
        forum.aTitle = sectionTitle
        favorite.forum = forum
        favorite.topics = NSMutableArray(array: topicIDs.map(makeTopic(postID:)))
        return favorite
    }

    private func makeTopic(postID: Int) -> Topic {
        let topic = Topic()
        topic.postID = Int32(postID)
        topic._aTitle = "Topic \(postID)"
        topic.catID = 13
        return topic
    }
}

private final class FavoritesLoaderStub: FavoritesLoading {
    func fetchFavorites(completion: @escaping FavoritesLoadCompletion) {
        completion([], nil)
    }
}
