import XCTest
@testable import HFRswift

@MainActor
final class AccountsStoreTests: XCTestCase {
    func testRefreshLoadsAccountsFromService() {
        let mockService = MockAccountSessionService()
        mockService.accounts = [
            Account(id: "alpha", displayName: "Alpha", isMain: false, avatarData: nil),
            Account(id: "beta", displayName: "Beta", isMain: true, avatarData: nil)
        ]

        let store = AccountsStore(accountSessionService: mockService)

        XCTAssertEqual(store.accounts.count, 2)
        XCTAssertEqual(store.currentAccount?.id, "beta")
        XCTAssertEqual(mockService.fetchAccountsCallCount, 1)
    }

    func testSetMainDelegatesToServiceAndRefreshes() {
        let mockService = MockAccountSessionService()
        mockService.accounts = [
            Account(id: "alpha", displayName: "Alpha", isMain: true, avatarData: nil),
            Account(id: "beta", displayName: "Beta", isMain: false, avatarData: nil)
        ]

        let store = AccountsStore(accountSessionService: mockService)
        let beta = mockService.accounts[1]

        store.setMain(beta)

        XCTAssertEqual(mockService.setMainAccountCalls, ["beta"])
        XCTAssertGreaterThanOrEqual(mockService.fetchAccountsCallCount, 2)
    }

    func testDeleteCurrentDelegatesToService() {
        let mockService = MockAccountSessionService()
        mockService.accounts = [
            Account(id: "alpha", displayName: "Alpha", isMain: true, avatarData: nil)
        ]

        let store = AccountsStore(accountSessionService: mockService)
        store.deleteCurrent()

        XCTAssertEqual(mockService.deleteAccountCalls, ["alpha"])
    }

    func testAddAccountDelegatesToServiceAndRefreshes() async throws {
        let mockService = MockAccountSessionService()
        mockService.accounts = [
            Account(id: "alpha", displayName: "Alpha", isMain: true, avatarData: nil)
        ]

        let store = AccountsStore(accountSessionService: mockService)
        try await store.addAccount(pseudo: "newbie", password: "secret")

        XCTAssertEqual(mockService.addAccountCalls.count, 1)
        XCTAssertEqual(mockService.addAccountCalls.first?.pseudo, "newbie")
        XCTAssertEqual(mockService.addAccountCalls.first?.password, "secret")
        XCTAssertGreaterThanOrEqual(mockService.fetchAccountsCallCount, 2)
    }
}

private final class MockAccountSessionService: AccountSessionService {
    var accounts: [Account] = []
    var fetchAccountsCallCount = 0
    var setMainAccountCalls: [String] = []
    var deleteAccountCalls: [String] = []
    var addAccountCalls: [(pseudo: String, password: String)] = []

    func fetchAccounts() -> [Account] {
        fetchAccountsCallCount += 1
        return accounts
    }

    func setMainAccount(id: String) {
        setMainAccountCalls.append(id)
    }

    func deleteAccount(id: String) {
        deleteAccountCalls.append(id)
    }

    func addAccount(pseudo: String, password: String) async throws {
        addAccountCalls.append((pseudo, password))
    }

    func makeReplySessionContext(cookieStorage: HTTPCookieStorage) throws -> ReplySessionContext {
        ReplySessionContext(pseudoDisplay: "mock", hashCheck: "mock-hash")
    }
}

@MainActor
final class CategoriesFlowViewModelTests: XCTestCase {
    func testCategoriesLoadSuccessPublishesForumsAndClearsError() {
        let loader = ForumsLoaderSpy()
        let viewModel = CategoriesListViewModel(forumsLoader: loader)
        let expectedForum = makeForum(title: "Programmation")

        viewModel.load()

        XCTAssertTrue(viewModel.isLoading)
        XCTAssertEqual(loader.completions.count, 1)

        loader.completions[0]([expectedForum], nil)
        flushMainQueue()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.forums.count, 1)
        XCTAssertEqual(viewModel.forums.first?.aTitle, "Programmation")
    }

    func testCategoriesLoadErrorClearsForumsAndPublishesError() {
        let loader = ForumsLoaderSpy()
        let viewModel = CategoriesListViewModel(forumsLoader: loader)
        viewModel.forums = [makeForum(title: "Ancien forum")]

        viewModel.load()

        XCTAssertTrue(viewModel.isLoading)
        XCTAssertEqual(loader.completions.count, 1)

        let expectedError = NSError(domain: "CategoriesFlowViewModelTests", code: 42)
        loader.completions[0](nil, expectedError)
        flushMainQueue()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.forums.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testForumTopicsLoadForwardsSelectedFlagAndPublishesTopics() {
        let loader = ForumTopicsLoaderSpy()
        let forum = makeForum(title: "Hardware")
        let viewModel = ForumTopicsListViewModel(forum: forum, topicsLoader: loader)
        let expectedTopic = makeTopic(title: "Thread #1")

        viewModel.selectedFlag = .tracked
        viewModel.load()

        XCTAssertTrue(viewModel.isLoading)
        XCTAssertEqual(loader.requests.count, 1)
        XCTAssertTrue(loader.requests[0].forum === forum)
        XCTAssertEqual(loader.requests[0].flag, .tracked)

        loader.requests[0].completion([expectedTopic], nil)
        flushMainQueue()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.topics.count, 1)
        XCTAssertEqual(viewModel.topics.first?._aTitle, "Thread #1")
    }

    func testForumTopicsIgnoresStaleCompletionWhenNewerLoadExists() {
        let loader = ForumTopicsLoaderSpy()
        let forum = makeForum(title: "Software")
        let viewModel = ForumTopicsListViewModel(forum: forum, topicsLoader: loader)
        let expectedTopic = makeTopic(title: "Thread récent")

        viewModel.selectedFlag = .all
        viewModel.load()
        viewModel.selectedFlag = .favorites
        viewModel.load()

        XCTAssertEqual(loader.requests.count, 2)

        let cancellation = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        loader.requests[0].completion(nil, cancellation)
        loader.requests[1].completion([expectedTopic], nil)
        flushMainQueue()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.topics.count, 1)
        XCTAssertEqual(viewModel.topics.first?._aTitle, "Thread récent")
    }

    func testForumTopicsCancellationForCurrentRequestKeepsExistingTopics() {
        let loader = ForumTopicsLoaderSpy()
        let forum = makeForum(title: "Windows")
        let viewModel = ForumTopicsListViewModel(forum: forum, topicsLoader: loader)
        let initialTopic = makeTopic(title: "Stable topic")

        viewModel.load()
        XCTAssertEqual(loader.requests.count, 1)
        loader.requests[0].completion([initialTopic], nil)
        flushMainQueue()
        XCTAssertEqual(viewModel.topics.count, 1)

        viewModel.load()
        XCTAssertEqual(loader.requests.count, 2)
        let cancellation = NSError(domain: "ASIHTTPRequestErrorDomain", code: 4)
        loader.requests[1].completion(nil, cancellation)
        flushMainQueue()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.topics.count, 1)
        XCTAssertEqual(viewModel.topics.first?._aTitle, "Stable topic")
    }

    private func flushMainQueue() {
        let expectation = expectation(description: "flushMainQueue")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    private func makeForum(title: String) -> Forum {
        let forum = Forum()
        forum.aTitle = title
        forum.aURL = "https://forum.hardware.fr/hfr/\(title)"
        return forum
    }

    private func makeTopic(title: String) -> Topic {
        let topic = Topic()
        topic._aTitle = title
        topic.aURL = "https://forum.hardware.fr/forum2.php?topic=\(title)"
        return topic
    }
}

private final class ForumsLoaderSpy: ForumsLoading {
    private(set) var completions: [ForumsLoadCompletion] = []

    func fetchForums(completion: @escaping ForumsLoadCompletion) {
        completions.append(completion)
    }
}

private final class ForumTopicsLoaderSpy: ForumTopicsLoading {
    struct Request {
        let forum: Forum
        let flag: TopicListFlag
        let completion: TopicsLoadCompletion
    }

    private(set) var requests: [Request] = []

    func fetchTopics(for forum: Forum, flag: TopicListFlag, completion: @escaping TopicsLoadCompletion) {
        requests.append(Request(forum: forum, flag: flag, completion: completion))
    }
}
