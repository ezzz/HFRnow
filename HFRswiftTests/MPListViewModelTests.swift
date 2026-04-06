import XCTest
@testable import HFRswift

final class MPListViewModelTests: XCTestCase {
    func testEnsureLoadedTriggersInitialRequestOnlyOnce() {
        let loader = MPTopicsLoaderSpy()
        let viewModel = MPListViewModel(topicsLoader: loader)

        viewModel.ensureLoaded()
        viewModel.ensureLoaded()

        XCTAssertEqual(loader.completions.count, 1)
    }

    func testLoadIfStaleSkipsRecentSuccessfulLoad() {
        let loader = MPTopicsLoaderSpy()
        let viewModel = MPListViewModel(topicsLoader: loader)

        viewModel.load()
        XCTAssertEqual(loader.completions.count, 1)

        loader.completions[0]([makeTopic(title: "Premier MP")], nil)
        flushMainQueue()

        viewModel.loadIfStale(maxAge: 60)

        XCTAssertEqual(loader.completions.count, 1)
    }

    func testLoadIfStaleRefreshesWhenDataIsExpired() {
        let loader = MPTopicsLoaderSpy()
        let viewModel = MPListViewModel(topicsLoader: loader)

        viewModel.load()
        XCTAssertEqual(loader.completions.count, 1)

        loader.completions[0]([makeTopic(title: "Premier MP")], nil)
        flushMainQueue()

        viewModel.loadIfStale(maxAge: 0)

        XCTAssertEqual(loader.completions.count, 2)
    }

    func testEnsureLoadedRetriesAfterError() {
        let loader = MPTopicsLoaderSpy()
        let viewModel = MPListViewModel(topicsLoader: loader)

        viewModel.load()
        XCTAssertEqual(loader.completions.count, 1)

        loader.completions[0](nil, NSError(domain: "MPListViewModelTests", code: 42))
        flushMainQueue()

        viewModel.ensureLoaded()

        XCTAssertEqual(loader.completions.count, 2)
    }

    private func flushMainQueue() {
        let expectation = expectation(description: "flushMainQueue")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    private func makeTopic(title: String) -> Topic {
        let topic = Topic()
        topic._aTitle = title
        return topic
    }
}

private final class MPTopicsLoaderSpy: MPTopicsLoading {
    var completions: [TopicsLoadCompletion] = []

    func fetchTopics(completion: @escaping TopicsLoadCompletion) {
        completions.append(completion)
    }
}
