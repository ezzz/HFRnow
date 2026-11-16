@testable import SwiftHFR
import Foundation
import HFRModels
import Testing

struct TopicRowInfoLineTests {
    private let now = Date(timeIntervalSince1970: 1_794_000_000)

    private func topic(
        pages: Int = 1, flag: TopicFlag? = nil, current: Int? = nil, poll: Bool = false, starter: String = "starter", last: LastPost? = nil
    ) -> TopicSummary {
        TopicSummary(
            title: "t", path: "/p", repliesCount: 40, pageCount: pages, lastPost: last, starterOrInterlocutors: starter,
            flag: flag, flagPath: flag == nil ? nil : "/f", currentPage: current, isPoll: poll
        )
    }

    @Test("Dates: relative under 24 h, then dd/MM/yy")
    func dates() {
        #expect(TopicRowInfoLine.dateLabel(now.addingTimeInterval(-13 * 60), now: now) == "il y a 13 min")
        #expect(TopicRowInfoLine.dateLabel(now.addingTimeInterval(-3 * 3600 - 59), now: now) == "il y a 3 h")
        #expect(TopicRowInfoLine.dateLabel(now.addingTimeInterval(60), now: now) == "il y a 1 min")
        // 2026-11-06 12:00 UTC is 13:00 in Paris.
        let old = Date(timeIntervalSince1970: 1_793_966_400)
        #expect(TopicRowInfoLine.dateLabel(old, now: old.addingTimeInterval(25 * 3600)) == "06/11/26")
    }

    @Test("Leading: ⚑ lue / total when flagged, else the page count with the poll mark")
    func leading() {
        #expect(TopicRowInfoLine.leading(topic(pages: 5, flag: .blue, current: 2)) == "⚑ 2 / 5")
        #expect(TopicRowInfoLine.leading(topic(pages: 5, flag: .blue, current: 2), showsFlag: false) == "5 pages")
        #expect(TopicRowInfoLine.leading(topic(pages: 1)) == "1 page")
        #expect(TopicRowInfoLine.leading(topic(pages: 3, poll: true)) == "3 pages \u{2263}")
    }

    @Test("Trailing: the last poster, never the starter, and nothing without a dated last post")
    func trailing() {
        let post = LastPost(author: "last", path: "/m", date: now.addingTimeInterval(-13 * 60))
        #expect(TopicRowInfoLine.trailing(topic(last: post), now: now) == "last - il y a 13 min")
        #expect(TopicRowInfoLine.trailing(topic(last: LastPost(author: "last", path: "/m")), now: now) == nil)
        #expect(TopicRowInfoLine.trailing(topic(), now: now) == nil)
    }

    @Test("The default row shows neither a reply count nor the starter nor a star")
    func noRepliesNoStar() {
        let post = LastPost(author: "last", path: "/m", date: now.addingTimeInterval(-60))
        let t = topic(pages: 4, starter: "starter", last: post)
        let line = TopicRowInfoLine.leading(t) + " " + (TopicRowInfoLine.trailing(t, now: now) ?? "")
        #expect(!line.contains("réponse"))
        #expect(!line.contains("40"))
        #expect(!line.contains("starter"))
        #expect(TopicRowStyle.current == .legacy)
    }
}
