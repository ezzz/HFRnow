import Foundation
import Testing
@testable import HFRModels

@Suite struct FavoritesPageTests {
    private func topic(_ title: String, date: TimeInterval?) -> TopicSummary {
        TopicSummary(
            title: title,
            path: "/\(title)",
            lastPost: date.map { LastPost(author: "a", path: "/p", date: Date(timeIntervalSince1970: $0)) }
        )
    }

    @Test func topicsByLastPostAreNewestFirstUndatedLastTiesInPageOrder() {
        let page = FavoritesPage(sections: [
            FavoriteSection(forum: ForumLink(title: "A", path: "/a"), topics: [
                topic("undated1", date: nil), topic("old", date: 10), topic("tieFirst", date: 50)
            ]),
            FavoriteSection(forum: ForumLink(title: "B", path: "/b"), topics: [
                topic("new", date: 90), topic("tieSecond", date: 50), topic("undated2", date: nil)
            ])
        ])
        #expect(page.topicsByLastPost.map(\.title) == ["new", "tieFirst", "tieSecond", "old", "undated1", "undated2"])
    }

    @Test func descriptionsShowTheNotice() {
        let page = FavoritesPage(notice: "Aucun sujet")
        #expect(page.description.contains("Aucun sujet"))
        #expect(String(describing: Mirror(reflecting: page).children.map { "\($0.value)" }).contains("Aucun sujet"))
    }

    @Test func descriptionsHideTheToken() {
        let page = FavoritesPage(hashCheck: "0123456789abcdef0123456789abcdef")
        #expect(!page.description.contains("0123456789abcdef"))
        #expect(!String(reflecting: page).contains("0123456789abcdef"))
        #expect(!String(describing: Mirror(reflecting: page).children.map { "\($0.value)" }).contains("0123456789abcdef"))
    }
}
