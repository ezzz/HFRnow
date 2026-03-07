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
        let controller = MessagesControllerStub(
            result: .success(html: "<html>ok</html>", topicAnswerURL: "https://forum.hardware.fr/reply"),
            messageActionsByIndex: [
                2: [
                    "quoteURL": "https://forum.hardware.fr/message.php?post=42",
                    "profileURL": "https://forum.hardware.fr/profil/test",
                    "privateMessageURL": "https://forum.hardware.fr/message.php?cat=prive",
                    "postID": "t123",
                    "editURL": "https://forum.hardware.fr/edit.php?post=42",
                    "favoriteURL": "https://forum.hardware.fr/fav.php?post=42",
                    "alertURL": "https://forum.hardware.fr/alerte.php?post=42",
                    "permalinkURL": "https://forum.hardware.fr/forum2.php?post=42#t42",
                    "authorName": "Pseudo",
                    "quoteJS": "javascript:qreply(13,432,61999,55767559); return false;",
                    "isOwnMessage": "1",
                    "canBeFavorite": "1",
                    "isPrivateCategory": "0",
                    "canAQ": "1",
                    "canBookmark": "1",
                    "canDelete": "1",
                    "topicID": "61999",
                    "topicCategory": "13",
                    "topicTitle": "BashHFr"
                ]
            ]
        )
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
            XCTAssertEqual(content.messageActionsByIndex[2]?.quoteURL?.absoluteString, "https://forum.hardware.fr/message.php?post=42")
            XCTAssertEqual(content.messageActionsByIndex[2]?.profileURL?.absoluteString, "https://forum.hardware.fr/profil/test")
            XCTAssertEqual(content.messageActionsByIndex[2]?.privateMessageURL?.absoluteString, "https://forum.hardware.fr/message.php?cat=prive")
            XCTAssertEqual(content.messageActionsByIndex[2]?.postID, "t123")
            XCTAssertEqual(content.messageActionsByIndex[2]?.editURL?.absoluteString, "https://forum.hardware.fr/edit.php?post=42")
            XCTAssertEqual(content.messageActionsByIndex[2]?.favoriteURL?.absoluteString, "https://forum.hardware.fr/fav.php?post=42")
            XCTAssertEqual(content.messageActionsByIndex[2]?.alertURL?.absoluteString, "https://forum.hardware.fr/alerte.php?post=42")
            XCTAssertEqual(content.messageActionsByIndex[2]?.permalinkURL?.absoluteString, "https://forum.hardware.fr/forum2.php?post=42#t42")
            XCTAssertEqual(content.messageActionsByIndex[2]?.authorName, "Pseudo")
            XCTAssertEqual(content.messageActionsByIndex[2]?.quoteJS, "javascript:qreply(13,432,61999,55767559); return false;")
            XCTAssertEqual(content.messageActionsByIndex[2]?.isOwnMessage, true)
            XCTAssertEqual(content.messageActionsByIndex[2]?.canBeFavorite, true)
            XCTAssertEqual(content.messageActionsByIndex[2]?.isPrivateCategory, false)
            XCTAssertEqual(content.messageActionsByIndex[2]?.canAQ, true)
            XCTAssertEqual(content.messageActionsByIndex[2]?.canBookmark, true)
            XCTAssertEqual(content.messageActionsByIndex[2]?.canDelete, true)
            XCTAssertEqual(content.messageActionsByIndex[2]?.topicID, "61999")
            XCTAssertEqual(content.messageActionsByIndex[2]?.topicCategory, "13")
            XCTAssertEqual(content.messageActionsByIndex[2]?.topicTitle, "BashHFr")
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

    func testObjCTopicPageLoaderKeepsBooleanOnlyMessageActionsEntries() {
        let controller = MessagesControllerStub(
            result: .success(html: "<html>ok</html>", topicAnswerURL: nil),
            messageActionsByIndex: [
                7: [
                    "isOwnMessage": "0",
                    "canBeFavorite": "0",
                    "isPrivateCategory": "0",
                    "canAQ": "1",
                    "canBookmark": "1",
                    "canDelete": "0",
                    "topicID": "61999",
                    "topicCategory": "13",
                    "topicTitle": "BashHFr"
                ]
            ]
        )
        let loader = ObjCTopicPageLoader(controller: controller)

        let expectation = expectation(description: "topic page boolean-only message actions")
        var receivedResult: Result<TopicPageContent, Error>?

        loader.fetchTopicPage(url: "https://forum.hardware.fr/topic", anchor: nil) { result in
            receivedResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)

        switch receivedResult {
        case .success(let content):
            let actions = content.messageActionsByIndex[7]
            XCTAssertNotNil(actions)
            XCTAssertEqual(actions?.canAQ, true)
            XCTAssertEqual(actions?.canBookmark, true)
            XCTAssertEqual(actions?.topicID, "61999")
            XCTAssertEqual(actions?.topicCategory, "13")
            XCTAssertEqual(actions?.topicTitle, "BashHFr")
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        case .none:
            XCTFail("Expected a result")
        }
    }

    func testObjCTopicPageLoaderParsesTrueAndYesBooleanFlags() {
        let controller = MessagesControllerStub(
            result: .success(html: "<html>ok</html>", topicAnswerURL: nil),
            messageActionsByIndex: [
                11: [
                    "canAQ": "yes",
                    "canBookmark": "true",
                    "canDelete": "false"
                ]
            ]
        )
        let loader = ObjCTopicPageLoader(controller: controller)

        let expectation = expectation(description: "topic page yes/true flags")
        var receivedResult: Result<TopicPageContent, Error>?

        loader.fetchTopicPage(url: "https://forum.hardware.fr/topic", anchor: nil) { result in
            receivedResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)

        switch receivedResult {
        case .success(let content):
            let actions = content.messageActionsByIndex[11]
            XCTAssertNotNil(actions)
            XCTAssertTrue(actions?.canAQ == true)
            XCTAssertTrue(actions?.canBookmark == true)
            XCTAssertFalse(actions?.canDelete == true)
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        case .none:
            XCTFail("Expected a result")
        }
    }

    func testObjCTopicPageLoaderDropsEmptyMessageActionsEntries() {
        let controller = MessagesControllerStub(
            result: .success(html: "<html>ok</html>", topicAnswerURL: nil),
            messageActionsByIndex: [
                3: [
                    "quoteURL": " ",
                    "profileURL": " ",
                    "authorName": " ",
                    "isOwnMessage": "0",
                    "canBeFavorite": "0",
                    "isPrivateCategory": "0",
                    "canAQ": "0",
                    "canBookmark": "0",
                    "canDelete": "0",
                    "topicID": " "
                ]
            ]
        )
        let loader = ObjCTopicPageLoader(controller: controller)

        let expectation = expectation(description: "topic page drops empty entry")
        var receivedResult: Result<TopicPageContent, Error>?

        loader.fetchTopicPage(url: "https://forum.hardware.fr/topic", anchor: nil) { result in
            receivedResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)

        switch receivedResult {
        case .success(let content):
            XCTAssertNil(content.messageActionsByIndex[3])
            XCTAssertTrue(content.messageActionsByIndex.isEmpty)
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
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

    func testQuickActionsDefaultsForFavoritesHideFirstPage() {
        let config = TopicQuickActionPolicy.defaults(for: .favorites)

        XCTAssertFalse(config.showOpenFirstPage)
        XCTAssertTrue(config.showOpenLastPage)
        XCTAssertTrue(config.showOpenLastReply)
        XCTAssertTrue(config.showOpenPagePicker)
        XCTAssertTrue(config.showCopyLink)
    }

    func testQuickActionsDefaultsForMessagesHideLastReply() {
        let config = TopicQuickActionPolicy.defaults(for: .messages)

        XCTAssertTrue(config.showOpenFirstPage)
        XCTAssertTrue(config.showOpenLastPage)
        XCTAssertFalse(config.showOpenLastReply)
        XCTAssertTrue(config.showOpenPagePicker)
        XCTAssertTrue(config.showCopyLink)
    }

    func testQuickActionsDefaultsForForumKeepAllPrimaryActions() {
        let config = TopicQuickActionPolicy.defaults(for: .forum(selectedFlag: .all))

        XCTAssertTrue(config.showOpenFirstPage)
        XCTAssertTrue(config.showOpenLastPage)
        XCTAssertTrue(config.showOpenLastReply)
        XCTAssertTrue(config.showOpenPagePicker)
        XCTAssertTrue(config.showCopyLink)
    }

    func testLastReplyURLForForumPrefersLastPostURL() {
        let topic = makeTopic(
            url: "https://forum.hardware.fr/hfr/test/liste_sujet-1.htm",
            lastPostURL: "https://forum.hardware.fr/hfr/test/liste_sujet-23.htm#t42",
            currentPage: 4,
            maxPage: 23
        )
        topic.aURLOfLastPage = "https://forum.hardware.fr/hfr/test/liste_sujet-23.htm"

        let url = TopicQuickActionPolicy.lastReplyURL(for: topic, context: .forum(selectedFlag: .all))

        XCTAssertEqual(url, topic.aURLOfLastPost)
    }

    func testLastReplyURLForFavoritesPrefersTopicURL() {
        let topic = makeTopic(
            url: "https://forum.hardware.fr/hfr/test/liste_sujet-7.htm",
            lastPostURL: "https://forum.hardware.fr/hfr/test/liste_sujet-31.htm#t99",
            currentPage: 7,
            maxPage: 31
        )

        let url = TopicQuickActionPolicy.lastReplyURL(for: topic, context: .favorites)

        XCTAssertEqual(url, topic.aURL)
    }

    func testLastReplyURLForMessagesPrefersLastPostURL() {
        let topic = makeTopic(
            url: "https://forum.hardware.fr/hfr/test/liste_sujet-2.htm",
            lastPostURL: "https://forum.hardware.fr/hfr/test/liste_sujet-18.htm#t88",
            currentPage: 2,
            maxPage: 18
        )
        topic.aURLOfLastPage = "https://forum.hardware.fr/hfr/test/liste_sujet-18.htm"

        let url = TopicQuickActionPolicy.lastReplyURL(for: topic, context: .messages)

        XCTAssertEqual(url, topic.aURLOfLastPost)
    }

    func testCopyLinkNormalizesRelativeURLToAbsoluteForumURL() {
        let topic = makeTopic(
            url: "/hfr/test/liste_sujet-1.htm",
            currentPage: 1,
            maxPage: 3
        )
        topic.aURLOfFirstPage = "/hfr/test/liste_sujet-1.htm"

        let copied = TopicQuickActionPolicy.copyLink(for: topic)

        XCTAssertEqual(copied, "https://forum.hardware.fr/hfr/test/liste_sujet-1.htm")
    }

    func testCopyLinkKeepsAbsoluteURLUntouched() {
        let topic = makeTopic(
            url: "https://forum.hardware.fr/hfr/test/liste_sujet-1.htm",
            currentPage: 1,
            maxPage: 3
        )
        topic.aURLOfFirstPage = "https://forum.hardware.fr/hfr/test/liste_sujet-1.htm"

        let copied = TopicQuickActionPolicy.copyLink(for: topic)

        XCTAssertEqual(copied, topic.aURLOfFirstPage)
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

private final class FavoritesControllerStub: NSObject {
    enum Result {
        case success([Favorite])
        case failure(Error)
    }

    let result: Result
    private(set) var fetchCalled = false

    init(result: Result) {
        self.result = result
        super.init()
    }

    @objc(fetchContentWithCompletion:)
    func fetchContent(completion: @escaping ([Favorite]?, Error?) -> Void) {
        fetchCalled = true
        switch result {
        case .success(let favorites):
            completion(favorites, nil)
        case .failure(let error):
            completion(nil, error)
        }
    }
}

private final class MPControllerStub: UIViewController {
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

    @objc(fetchContentWithCompletion:)
    func fetchContent(completion: @escaping ([Topic]?, Error?) -> Void) {
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

private final class ForumsControllerStub: NSObject {
    enum Result {
        case success([Forum])
        case failure(Error)
    }

    let result: Result
    private(set) var fetchCalled = false

    init(result: Result) {
        self.result = result
        super.init()
    }

    @objc(fetchContentWithCompletion:)
    func fetchContent(completion: @escaping ([Forum]?, Error?) -> Void) {
        fetchCalled = true
        switch result {
        case .success(let forums):
            completion(forums, nil)
        case .failure(let error):
            completion(nil, error)
        }
    }
}

private final class ForumTopicsControllerStub: NSObject {
    enum Result {
        case success([Topic])
        case failure(Error)
    }

    let result: Result
    private(set) var fetchCalled = false
    private(set) var receivedForum: Forum?
    private(set) var receivedFlagIndex: Int?

    init(result: Result) {
        self.result = result
        super.init()
    }

    @objc(fetchContentForForum:flagIndex:completion:)
    func fetchContent(for forum: Forum, flagIndex: Int, completion: @escaping ([Topic]?, Error?) -> Void) {
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

private final class MessagesControllerStub: NSObject {
    enum Result {
        case success(html: String?, topicAnswerURL: String?)
        case failure(Error)
    }

    let result: Result
    let messageActionsByIndex: [NSNumber: [String: String]]
    private(set) var receivedTopicURL: String?
    private(set) var receivedAnchor: String?

    init(result: Result, messageActionsByIndex: [NSNumber: [String: String]] = [:]) {
        self.result = result
        self.messageActionsByIndex = messageActionsByIndex
        super.init()
    }

    @objc(fetchContentForTopicURL:anchor:completion:)
    func fetchContent(forTopicURL topicURL: String, anchor: String?, completion: @escaping (String?, String?, Error?) -> Void) {
        receivedTopicURL = topicURL
        receivedAnchor = anchor

        switch result {
        case .success(let html, let topicAnswerURL):
            completion(html, topicAnswerURL, nil)
        case .failure(let error):
            completion(nil, nil, error)
        }
    }

    @objc(swiftMessageActionsByIndex)
    func swiftMessageActionsByIndex() -> [NSNumber : [String : String]] {
        messageActionsByIndex
    }
}
