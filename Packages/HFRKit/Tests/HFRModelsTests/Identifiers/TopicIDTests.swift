import Testing
@testable import HFRModels

@Suite struct TopicIDTests {
    @Test func sameTopicNumberInDifferentCategoriesIsDifferent() {
        let first = TopicID(category: .forum(13), topic: 42)
        let second = TopicID(category: .forum(1), topic: 42)
        #expect(first != second)
        #expect(Set([first, second, first]).count == 2)
    }

    @Test func privateMessagesAreADistinctCategory() {
        #expect(TopicID(category: .privateMessages, topic: 42) != TopicID(category: .forum(42), topic: 42))
    }

    @Test func roundTrips() throws {
        let identifier = TopicID(category: .privateMessages, topic: 7)
        #expect(try roundTrip(identifier) == identifier)
    }
}
