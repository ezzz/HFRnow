import Testing
@testable import HFRModels

@Suite struct TopicListPathTests {
    @Test func defaultsToAllTopicsOnPageOne() {
        #expect(ForumCatalogue.topicListPath(categoryID: .forum(13))
            == "/forum1.php?config=hfr.inc&cat=13&page=1&subcat=&owntopic=0")
    }

    @Test(arguments: [
        (TopicListFilter.all, "0"),
        (TopicListFilter.flagged, "1"),
        (TopicListFilter.read, "2"),
        (TopicListFilter.favorites, "3")
    ])
    func filterSetsOwntopic(filter: TopicListFilter, value: String) {
        #expect(ForumCatalogue.topicListPath(categoryID: .forum(25), filter: filter, page: 1)
            == "/forum1.php?config=hfr.inc&cat=25&page=1&subcat=&owntopic=\(value)")
    }

    @Test func pageNumberIsWritten() {
        #expect(ForumCatalogue.topicListPath(categoryID: .forum(13), page: 12)
            == "/forum1.php?config=hfr.inc&cat=13&page=12&subcat=&owntopic=0")
    }

    @Test func builtPathsParseBackToTheSameCategory() throws {
        let path = try #require(ForumCatalogue.topicListPath(categoryID: .forum(5), filter: .read, page: 2))
        let query = try #require(path.split(separator: "?").last)
        let cat = query.split(separator: "&").first { $0.hasPrefix("cat=") }.map { $0.dropFirst(4) }
        #expect(cat.flatMap { CategoryID(queryValue: String($0)) } == .forum(5))
    }

    @Test func rejectsPageBelowOne() {
        #expect(ForumCatalogue.topicListPath(categoryID: .forum(13), page: 0) == nil)
        #expect(ForumCatalogue.topicListPath(categoryID: .forum(13), page: -3) == nil)
    }

    @Test func privateMessagesAreNotBuiltHere() {
        #expect(ForumCatalogue.topicListPath(categoryID: .privateMessages) == nil)
    }
}
