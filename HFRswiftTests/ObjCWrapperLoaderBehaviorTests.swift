import XCTest
@testable import HFRswift

final class ObjCWrapperLoaderBehaviorTests: XCTestCase {
    func testObjCFavoritesLoaderPassesThroughFavorites() {
        let expectedFavorites = [Favorite()]
        let controller = FavoritesControllerStub(result: .success(expectedFavorites))
        let loader = ObjCFavoritesLoader(controller: controller)

        let expectation = expectation(description: "favorites completion")
        var receivedFavorites: [Favorite]?
        var receivedError: Error?

        loader.fetchFavorites { favorites, error in
            receivedFavorites = favorites
            receivedError = error
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
        XCTAssertTrue(controller.fetchCalled)
        XCTAssertEqual(receivedFavorites?.count, expectedFavorites.count)
        XCTAssertNil(receivedError)
    }

    func testObjCFavoritesLoaderPassesThroughError() {
        let expectedError = NSError(domain: "ObjCWrapperLoaderBehaviorTests", code: 1)
        let controller = FavoritesControllerStub(result: .failure(expectedError))
        let loader = ObjCFavoritesLoader(controller: controller)

        let expectation = expectation(description: "favorites error completion")
        var receivedFavorites: [Favorite]?
        var receivedError: Error?

        loader.fetchFavorites { favorites, error in
            receivedFavorites = favorites
            receivedError = error
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
        XCTAssertTrue(controller.fetchCalled)
        XCTAssertNil(receivedFavorites)
        XCTAssertNotNil(receivedError)
    }

    func testObjCMPTopicsLoaderCallsLoadViewIfNeededBeforeFetchAndPassesTopics() {
        let expectedTopics = [Topic()]
        let controller = MPControllerStub(result: .success(expectedTopics))
        let loader = ObjCMPTopicsLoader(controller: controller)

        let expectation = expectation(description: "mp completion")
        var receivedTopics: [Topic]?
        var receivedError: Error?

        loader.fetchTopics { topics, error in
            receivedTopics = topics
            receivedError = error
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
        XCTAssertTrue(controller.loadViewIfNeededCalled)
        XCTAssertTrue(controller.fetchCalled)
        XCTAssertTrue(controller.didLoadViewIfNeededBeforeFetch)
        XCTAssertEqual(receivedTopics?.count, expectedTopics.count)
        XCTAssertNil(receivedError)
    }

    func testObjCForumsLoaderPassesThroughForums() {
        let expectedForums = [Forum()]
        let controller = ForumsControllerStub(result: .success(expectedForums))
        let loader = ObjCForumsLoader(controller: controller)

        let expectation = expectation(description: "forums completion")
        var receivedForums: [Forum]?
        var receivedError: Error?

        loader.fetchForums { forums, error in
            receivedForums = forums
            receivedError = error
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
        XCTAssertTrue(controller.fetchCalled)
        XCTAssertEqual(receivedForums?.count, expectedForums.count)
        XCTAssertNil(receivedError)
    }

    func testObjCForumTopicsLoaderForwardsForumAndFlag() {
        let forum = Forum()
        forum.aTitle = "Programmation"

        let expectedTopics = [Topic()]
        let controller = ForumTopicsControllerStub(result: .success(expectedTopics))
        let loader = ObjCForumTopicsLoader(controller: controller)

        let expectation = expectation(description: "forum topics completion")
        var receivedTopics: [Topic]?
        var receivedError: Error?

        loader.fetchTopics(for: forum, flag: .tracked) { topics, error in
            receivedTopics = topics
            receivedError = error
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
        XCTAssertTrue(controller.fetchCalled)
        XCTAssertTrue(controller.receivedForum === forum)
        XCTAssertEqual(controller.receivedFlagIndex, TopicListFlag.tracked.rawValue)
        XCTAssertEqual(receivedTopics?.count, expectedTopics.count)
        XCTAssertNil(receivedError)
    }

    func testObjCTopicPageLoaderMapsSuccessAndPassesURLAndAnchor() {
        let controller = MessagesControllerStub(result: .success(html: "<html>ok</html>", topicAnswerURL: "https://forum.hardware.fr/reply"))
        let loader = ObjCTopicPageLoader(controller: controller)

        let expectation = expectation(description: "topic page success")
        var receivedResult: Result<TopicPageContent, Error>?

        loader.fetchTopicPage(url: "https://forum.hardware.fr/topic?page=2", anchor: "msg-42") { result in
            receivedResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(controller.receivedTopicURL, "https://forum.hardware.fr/topic?page=2")
        XCTAssertEqual(controller.receivedAnchor, "msg-42")

        switch receivedResult {
        case .success(let content):
            XCTAssertEqual(content.html, "<html>ok</html>")
            XCTAssertEqual(content.topicAnswerURL?.absoluteString, "https://forum.hardware.fr/reply")
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        case .none:
            XCTFail("Expected a result")
        }
    }

    func testObjCTopicPageLoaderReturnsMissingHTMLWhenObjCReturnsNilHTMLWithoutError() {
        let controller = MessagesControllerStub(result: .success(html: nil, topicAnswerURL: nil))
        let loader = ObjCTopicPageLoader(controller: controller)

        let expectation = expectation(description: "topic page missing html")
        var receivedResult: Result<TopicPageContent, Error>?

        loader.fetchTopicPage(url: "https://forum.hardware.fr/topic", anchor: nil) { result in
            receivedResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)

        switch receivedResult {
        case .failure(let error):
            XCTAssertEqual(error.localizedDescription, TopicPageLoadingError.missingHTML.localizedDescription)
        case .success:
            XCTFail("Expected missingHTML failure")
        case .none:
            XCTFail("Expected a result")
        }
    }

    func testObjCTopicPageLoaderPassesThroughObjCError() {
        let expectedError = NSError(domain: "ObjCWrapperLoaderBehaviorTests", code: 2)
        let controller = MessagesControllerStub(result: .failure(expectedError))
        let loader = ObjCTopicPageLoader(controller: controller)

        let expectation = expectation(description: "topic page error")
        var receivedResult: Result<TopicPageContent, Error>?

        loader.fetchTopicPage(url: "https://forum.hardware.fr/topic", anchor: nil) { result in
            receivedResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)

        switch receivedResult {
        case .failure(let error):
            XCTAssertEqual((error as NSError).domain, expectedError.domain)
            XCTAssertEqual((error as NSError).code, expectedError.code)
        case .success:
            XCTFail("Expected error")
        case .none:
            XCTFail("Expected a result")
        }
    }
}

final class TopicOpenPolicyTests: XCTestCase {
    func testForumAllUsesTopicBaseURL() {
        let topic = makeTopic(
            url: "https://forum.hardware.fr/hfr/test/liste_sujet-1.htm",
            currentPage: 1,
            maxPage: 24
        )

        let decision = TopicOpenPolicy.defaultDecision(for: topic, context: .forum(selectedFlag: .all))

        XCTAssertEqual(decision.preferredURL, topic.aURL)
        XCTAssertEqual(decision.fallbackPage, 1)
    }

    func testForumFilteredUsesFlagURLWhenPresent() {
        let topic = makeTopic(
            url: "https://forum.hardware.fr/hfr/test/liste_sujet-1.htm",
            flagURL: "https://forum.hardware.fr/hfr/test/liste_sujet-18.htm",
            lastPostURL: "https://forum.hardware.fr/hfr/test/liste_sujet-24.htm",
            currentPage: 18,
            maxPage: 24
        )

        let decision = TopicOpenPolicy.defaultDecision(for: topic, context: .forum(selectedFlag: .tracked))

        XCTAssertEqual(decision.preferredURL, topic.aURLOfFlag)
        XCTAssertEqual(decision.fallbackPage, 18)
    }

    func testForumFilteredFallsBackToLastPostWhenNoFlagURL() {
        let topic = makeTopic(
            url: "https://forum.hardware.fr/hfr/test/liste_sujet-1.htm",
            lastPostURL: "https://forum.hardware.fr/hfr/test/liste_sujet-33.htm",
            currentPage: 3,
            maxPage: 33
        )

        let decision = TopicOpenPolicy.defaultDecision(for: topic, context: .forum(selectedFlag: .favorites))

        XCTAssertEqual(decision.preferredURL, topic.aURLOfLastPost)
        XCTAssertEqual(decision.fallbackPage, 33)
    }

    func testFavoritesUsesFlagURLWhenPresent() {
        let topic = makeTopic(
            url: "https://forum.hardware.fr/hfr/test/liste_sujet-1.htm",
            flagURL: "https://forum.hardware.fr/hfr/test/liste_sujet-7.htm",
            currentPage: 7,
            maxPage: 10
        )

        let decision = TopicOpenPolicy.defaultDecision(for: topic, context: .favorites)

        XCTAssertEqual(decision.preferredURL, topic.aURLOfFlag)
        XCTAssertEqual(decision.fallbackPage, 7)
    }

    func testMessagesUsesLastPostURLAndMaxPageFallback() {
        let topic = makeTopic(
            url: "https://forum.hardware.fr/hfr/test/liste_sujet-1.htm",
            lastPostURL: "https://forum.hardware.fr/hfr/test/liste_sujet-55.htm",
            currentPage: 8,
            maxPage: 55
        )

        let decision = TopicOpenPolicy.defaultDecision(for: topic, context: .messages)

        XCTAssertEqual(decision.preferredURL, topic.aURLOfLastPost)
        XCTAssertEqual(decision.fallbackPage, 55)
    }

    private func makeTopic(
        url: String,
        flagURL: String? = nil,
        lastPostURL: String? = nil,
        currentPage: Int,
        maxPage: Int
    ) -> Topic {
        let topic = Topic()
        topic.aURL = url
        topic.aURLOfFlag = flagURL
        topic.aURLOfLastPost = lastPostURL
        topic.curTopicPage = Int32(currentPage)
        topic.maxTopicPage = Int32(maxPage)
        return topic
    }
}

private final class FavoritesControllerStub: FavoritesTableViewController {
    enum Result {
        case success([Favorite])
        case failure(Error)
    }

    let result: Result
    private(set) var fetchCalled = false

    init(result: Result) {
        self.result = result
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func fetchContent(completion: (([Favorite]?, Error?) -> Void)!) {
        fetchCalled = true
        switch result {
        case .success(let favorites):
            completion(favorites, nil)
        case .failure(let error):
            completion(nil, error)
        }
    }
}

private final class MPControllerStub: HFRMPViewController {
    enum Result {
        case success([Topic])
        case failure(Error)
    }

    let result: Result
    private(set) var loadViewIfNeededCalled = false
    private(set) var fetchCalled = false
    private(set) var didLoadViewIfNeededBeforeFetch = false

    init(result: Result) {
        self.result = result
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadViewIfNeeded() {
        loadViewIfNeededCalled = true
    }

    override func fetchContent(completion: (([Topic]?, Error?) -> Void)!) {
        fetchCalled = true
        didLoadViewIfNeededBeforeFetch = loadViewIfNeededCalled

        switch result {
        case .success(let topics):
            completion(topics, nil)
        case .failure(let error):
            completion(nil, error)
        }
    }
}

private final class ForumsControllerStub: ForumsTableViewController {
    enum Result {
        case success([Forum])
        case failure(Error)
    }

    let result: Result
    private(set) var fetchCalled = false

    init(result: Result) {
        self.result = result
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func fetchContent(completion: (([Forum]?, Error?) -> Void)!) {
        fetchCalled = true
        switch result {
        case .success(let forums):
            completion(forums, nil)
        case .failure(let error):
            completion(nil, error)
        }
    }
}

private final class ForumTopicsControllerStub: TopicsTableViewController {
    enum Result {
        case success([Topic])
        case failure(Error)
    }

    let result: Result
    private(set) var fetchCalled = false
    private(set) var receivedForum: Forum?
    private(set) var receivedFlagIndex: Int?

    override init() {
        self.result = .success([])
        super.init()
    }

    init(result: Result) {
        self.result = result
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func fetchContent(for forum: Forum!, flagIndex: Int, completion: (([Topic]?, Error?) -> Void)!) {
        fetchCalled = true
        receivedForum = forum
        receivedFlagIndex = flagIndex

        switch result {
        case .success(let topics):
            completion(topics, nil)
        case .failure(let error):
            completion(nil, error)
        }
    }
}

private final class MessagesControllerStub: MessagesTableViewController {
    enum Result {
        case success(html: String?, topicAnswerURL: String?)
        case failure(Error)
    }

    let result: Result
    private(set) var receivedTopicURL: String?
    private(set) var receivedAnchor: String?

    init(result: Result) {
        self.result = result
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func fetchContent(forTopicURL topicURL: String!, anchor: String?, completion: @escaping (String?, String?, Error?) -> Void) {
        receivedTopicURL = topicURL
        receivedAnchor = anchor

        switch result {
        case .success(let html, let topicAnswerURL):
            completion(html, topicAnswerURL, nil)
        case .failure(let error):
            completion(nil, nil, error)
        }
    }
}
