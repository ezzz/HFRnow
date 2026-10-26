import Foundation
import HFRModels
import Testing
@testable import HFRStorage

@Suite struct DraftContextTests {
    private let topic = TopicID(category: .forum(13), topic: 4242)

    @Test func everyContextHasADistinctKey() {
        let contexts: [DraftContext] = [
            .reply(topic: topic, page: 1), .reply(topic: topic, page: 2),
            .reply(topic: TopicID(category: .forum(14), topic: 4242), page: 1),
            .reply(topic: TopicID(category: .forum(13), topic: 4243), page: 1),
            .newTopic(forum: .forum(13)), .newTopic(forum: .forum(14)), .newTopic(forum: .privateMessages),
            .privateMessage(recipient: "Marc"), .privateMessage(recipient: "Marcel"),
            .edit(topic: topic, post: 7), .edit(topic: topic, post: 8), .legacyGlobal
        ]
        #expect(Set(contexts.map(\.storageKey)).count == contexts.count)
    }

    @Test func privateMessageRecipientIgnoresCaseAndZeroWidthSpaces() {
        let noisy = DraftContext.privateMessage(recipient: "Ma\u{200B}RC")
        #expect(noisy.storageKey == DraftContext.privateMessage(recipient: "marc").storageKey)
    }

    @Test func replyAndEditOfTheSameTopicNeverCollide() {
        #expect(DraftContext.reply(topic: topic, page: 7).storageKey != DraftContext.edit(topic: topic, post: 7).storageKey)
    }

    @Test func contextsRoundTripThroughJSON() throws {
        let contexts: [DraftContext] = [
            .reply(topic: topic, page: 3), .newTopic(forum: .forum(13)), .privateMessage(recipient: "Marc"),
            .edit(topic: TopicID(category: .privateMessages, topic: 9), post: 2), .legacyGlobal
        ]
        let data = try JSONEncoder().encode(contexts)
        #expect(try JSONDecoder().decode([DraftContext].self, from: data) == contexts)
    }
}
