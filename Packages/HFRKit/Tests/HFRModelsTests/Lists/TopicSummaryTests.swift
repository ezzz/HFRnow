import Foundation
import Testing
@testable import HFRModels

@Suite struct TopicSummaryTests {
    private func makeTopic(topicID: TopicID? = TopicID(category: .forum(13), topic: 1234)) -> TopicSummary {
        TopicSummary(
            topicID: topicID,
            title: "Le topic",
            path: "/forum2.php?config=hfr.inc&cat=13&post=1234&page=1",
            repliesCount: 120,
            pageCount: 3,
            lastPagePath: "/forum2.php?config=hfr.inc&cat=13&post=1234&page=3",
            lastPost: LastPost(
                author: "Alice",
                path: "/forum2.php?cat=13&post=1234&page=3#t99",
                date: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            starterOrInterlocutors: "Bob",
            flag: .blue,
            flagPath: "/forum2.php?config=hfr.inc&cat=13&post=1234&page=2#t55",
            currentPage: 2,
            readState: .unread,
            isSticky: true,
            isClosed: false,
            isPoll: true,
            searchHit: SearchHit(postPath: "/forum2.php?cat=13&post=1234#t7", snippet: "...")
        )
    }

    @Test func identityUsesTopicIDWhenKnown() {
        #expect(makeTopic().id == "topic:13-1234")
    }

    @Test func identityFallsBackToThePathAndStaysStable() {
        let first = makeTopic(topicID: nil)
        let second = makeTopic(topicID: nil)
        #expect(first.id == "path:/forum2.php?config=hfr.inc&cat=13&post=1234&page=1")
        #expect(first.id == second.id)
    }

    @Test func identityDistinguishesPrivateMessagesFromAForumWithTheSameNumber() {
        let forum = makeTopic(topicID: TopicID(category: .forum(1), topic: 5))
        let privateMessage = makeTopic(topicID: TopicID(category: .privateMessages, topic: 5))
        #expect(forum.id != privateMessage.id)
    }

    @Test func identityIsPreservedByEncoding() throws {
        let topic = makeTopic()
        #expect(try roundTrip(topic).id == topic.id)
    }

    @Test func fullyPopulatedTopicRoundTrips() throws {
        let topic = makeTopic()
        #expect(try roundTrip(topic) == topic)
    }

    @Test func minimalTopicRoundTripsAndDefaultsDescribeASinglePage() throws {
        let topic = TopicSummary(title: "t", path: "/p")
        #expect(topic.pageCount == 1)
        #expect(topic.lastPagePath == "/p")
        #expect(topic.readState == .unknown)
        #expect(try roundTrip(topic) == topic)
    }

    @Test(arguments: [0, -3])
    func pageCountIsRaisedToOneByTheInitializer(value: Int) {
        #expect(TopicSummary(title: "t", path: "/p", pageCount: value).pageCount == 1)
    }

    @Test func pageCountIsRaisedToOneOnMutation() {
        var topic = makeTopic()
        topic.pageCount = 0
        #expect(topic.pageCount == 1)
    }

    @Test func pageCountIsRaisedToOneOnDecoding() throws {
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(makeTopic())) as? [String: Any]
        )
        object["pageCount"] = 0
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(TopicSummary.self, from: data).pageCount == 1)
    }

    @Test func topicsWithDifferentFlagsAreNotEqual() {
        var other = makeTopic()
        other.flag = .red
        #expect(makeTopic() != other)
    }

    @Test func flagAndFilterRawValuesMatchTheWire() {
        #expect(TopicFlag.red.rawValue == "red")
        #expect(TopicFlag.blue.rawValue == "blue")
        #expect(TopicFlag.yellow.rawValue == "yellow")
        #expect(TopicListFilter.all.rawValue == 0)
        #expect(TopicListFilter.flagged.rawValue == 1)
        #expect(TopicListFilter.read.rawValue == 2)
        #expect(TopicListFilter.favorites.rawValue == 3)
    }
}
