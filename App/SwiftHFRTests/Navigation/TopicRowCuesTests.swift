@testable import SwiftHFR
import HFRModels
import SwiftUI
import Testing

struct TopicRowCuesTests {
    private func topic(
        flag: TopicFlag? = nil, flagPath: String? = nil, current: Int? = nil, pages: Int = 1, poll: Bool = false
    ) -> TopicSummary {
        TopicSummary(
            topicID: TopicID(category: .privateMessages, topic: 3_207_033),
            title: "subject",
            path: "/forum2.php?config=hfr.inc&cat=1&post=1",
            pageCount: pages,
            flag: flag,
            flagPath: flagPath ?? (flag == nil ? nil : "/user/delflag.php?topic=1"),
            currentPage: current,
            isPoll: poll
        )
    }

    @Test("The section header's bare count is spoken as topics")
    func topicCountLabel() {
        #expect(TopicRowCues.topicCountLabel(0) == "0 sujet")
        #expect(TopicRowCues.topicCountLabel(1) == "1 sujet")
        #expect(TopicRowCues.topicCountLabel(12) == "12 sujets")
    }

    @Test("Unread pages: hidden without a flag page or on the last page, else pageCount - currentPage")
    func unreadPages() {
        #expect(TopicRowCues.unreadPages(topic(pages: 5)) == nil)
        #expect(TopicRowCues.unreadPages(topic(flag: .blue, current: 5, pages: 5)) == nil)
        #expect(TopicRowCues.unreadPages(topic(flag: .blue, current: 2, pages: 5)) == 3)
        #expect(TopicRowCues.unreadPages(topic(current: 2, pages: 5)) == nil)
        #expect(TopicRowCues.unreadPages(topic(flag: .blue, current: 0, pages: 5)) == nil)
        // A flag of unknown colour still has its link: the capsule shows, as `hasFlag` says the row is flagged.
        #expect(TopicRowCues.unreadPages(topic(flagPath: "/user/delflag.php?topic=1", current: 2, pages: 5)) == 3)
        #expect(TopicRowCues.unreadPagesLabel(3) == "3 pages non lues")
        #expect(TopicRowCues.unreadPagesLabel(1) == "1 page non lue")
    }

    @Test("Footer: ⚑ cur / max, with the poll mark, only when the flag page is within the topic")
    func pageFooter() {
        #expect(TopicRowCues.pageFooter(topic(flag: .blue, current: 2, pages: 5)) == "⚑ 2 / 5")
        #expect(TopicRowCues.pageFooter(topic(flag: .blue, current: 2, pages: 5, poll: true)) == "⚑ \u{2263} 2 / 5")
        #expect(TopicRowCues.pageFooter(topic(pages: 5)) == nil)
        #expect(TopicRowCues.pageFooter(topic(current: 2, pages: 5)) == nil)
        #expect(TopicRowCues.pageFooter(topic(flagPath: "/user/delflag.php?topic=1", current: 2, pages: 5)) == "⚑ 2 / 5")
        #expect(TopicRowCues.pageFooter(topic(flag: .blue, current: 0, pages: 5)) == nil)
        #expect(TopicRowCues.pageFooter(topic(flag: .blue, current: 9, pages: 5)) == nil)
    }

    @Test("Accent per flag; the super favourite wins; the selected row has none")
    func accent() {
        #expect(TopicRowCues.accent(flag: .yellow, isSuperFavorite: false, isSelected: false) == .yellowFlag)
        #expect(TopicRowCues.accent(flag: .blue, isSuperFavorite: false, isSelected: false) == .blueFlag)
        #expect(TopicRowCues.accent(flag: .red, isSuperFavorite: false, isSelected: false) == .redFlag)
        #expect(TopicRowCues.accent(flag: nil, isSuperFavorite: false, isSelected: false) == nil)
        #expect(TopicRowCues.accent(flag: .blue, isSuperFavorite: true, isSelected: false) == .superFavorite)
        #expect(TopicRowCues.accent(flag: .blue, isSuperFavorite: true, isSelected: true) == nil)
    }

    @Test("The row tint takes the base of its list: the grouped card by default, clear in the sidebar column")
    func rowTintBases() throws {
        let grouped = try #require(TopicListView.rowTint(topic: topic(flag: .blue), isSuperFavorite: false, isSelected: false))
        #expect(grouped.base == .grouped)
        let sidebar = try #require(
            TopicListView.rowTint(topic: topic(flag: .blue), isSuperFavorite: true, isSelected: false, base: .clear)
        )
        #expect(sidebar.base == .clear)
    }

    @Test("The accent weight: quieter for a flag, full for the super favourite")
    func rowTintWeight() throws {
        let flagged = try #require(TopicListView.rowTint(topic: topic(flag: .blue), isSuperFavorite: false, isSelected: false))
        #expect(flagged.weight < 1)
        let sup = try #require(TopicListView.rowTint(topic: topic(), isSuperFavorite: true, isSelected: false))
        #expect(sup.weight == 1)
        #expect(TopicListView.rowTint(topic: topic(flag: .blue), isSuperFavorite: false, isSelected: true) == nil)
        // A flag removal HFR confirmed hides the icon, the capsule and the footer: the tint goes too.
        #expect(TopicListView.rowTint(topic: topic(flag: .blue), showsFlag: false, isSuperFavorite: false, isSelected: false) == nil)
    }

    @Test("A clickable section title keeps the category name as its label and says the action as a hint (#769)")
    func sectionTitleSpeech() {
        for title in ["Hardware", "Discussions"] {
            let speech = TopicRowCues.sectionTitleSpeech(title)
            #expect(speech.label == title)
            #expect(speech.hint == "Ouvrir le forum")
        }
        #expect(TopicRowCues.sectionTitleSpeech("Hardware").label != TopicRowCues.sectionTitleSpeech("Discussions").label)
    }
}
