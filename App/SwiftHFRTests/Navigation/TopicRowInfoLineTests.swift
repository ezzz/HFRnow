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

    @Test("Spoken leading: no glyph, the poll and the flag position in words (#1161)")
    func spokenLeading() {
        #expect(TopicRowInfoLine.spokenLeading(topic(pages: 12, flag: .blue, current: 3, poll: true)) == "Sondage, page 3 sur 12")
        #expect(TopicRowInfoLine.spokenLeading(topic(pages: 12, flag: .blue, current: 3)) == "Page 3 sur 12")
        #expect(TopicRowInfoLine.spokenLeading(topic(pages: 3, poll: true)) == "3 pages, sondage")
        #expect(TopicRowInfoLine.spokenLeading(topic(pages: 5, flag: .blue, current: 2), showsFlag: false) == "5 pages")
        #expect(TopicRowInfoLine.spokenLeading(topic(pages: 1)) == "1 page")
        let flaggedPoll = topic(pages: 3, flag: .red, current: 1, poll: true)
        for spoken in [TopicRowInfoLine.spokenLeading(flaggedPoll), TopicRowInfoLine.spokenLeading(topic(pages: 3, poll: true))] {
            #expect(!spoken.contains("⚑") && !spoken.contains("\u{2263}"))
        }
    }

    @Test("Dates: relative under 24 h, then dd/MM/yy")
    func dates() {
        #expect(TopicRowInfoLine.dateLabel(now.addingTimeInterval(-13 * 60), now: now) == "il y a 13 min")
        #expect(TopicRowInfoLine.dateLabel(now.addingTimeInterval(-3 * 3600 - 59), now: now) == "il y a 3 h")
        #expect(TopicRowInfoLine.dateLabel(now.addingTimeInterval(-20), now: now) == "il y a 1 min")
        // Ahead of the clock: "HH:mm" in Paris time (legacy `ObjCTopicListParser.m:431-433`); 21:20 UTC is 22:20 in Paris.
        #expect(TopicRowInfoLine.dateLabel(now.addingTimeInterval(60), now: now) == "22:21")
        // 2026-11-06 23:30 UTC is 00:30 on the 7th in Paris: the Paris zone, not UTC, decides the day.
        let late = Date(timeIntervalSince1970: 1_794_007_800)
        #expect(TopicRowInfoLine.dateLabel(late, now: late.addingTimeInterval(25 * 3600)) == "07/11/26")
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
        // No author: the date still shows (#857).
        let anonymous = LastPost(author: "", path: "/m", date: now.addingTimeInterval(-13 * 60))
        #expect(TopicRowInfoLine.trailing(topic(last: anonymous), now: now) == "il y a 13 min")
    }

    @Test("The default row shows neither a reply count nor the starter nor a star")
    @MainActor func noRepliesNoStar() {
        let post = LastPost(author: "last", path: "/m", date: now.addingTimeInterval(-60))
        let row = topic(pages: 4, starter: "starter", last: post)
        let line = TopicRowInfoLine.leading(row) + " " + (TopicRowInfoLine.trailing(row, now: now) ?? "")
        #expect(!line.contains("réponse"))
        #expect(!line.contains("40"))
        #expect(!line.contains("starter"))
        #expect(TopicRowStyle.current(nil) == .legacy)
    }
}

struct TopicSourceTitleTests {
    @Test("The Favoris tab's screen is titled Favoris whichever list it shows; the picker names legacy's two modes (#975, #824)")
    func favorisTabTitle() {
        #expect(TopicSource.flagged.navigationTitle == "Favoris")
        #expect(TopicSource.favorites.navigationTitle == "Favoris")
        #expect(TopicSource.flagged.title == "Drapeaux & Favoris")
        #expect(TopicSource.favorites.title == "Favoris uniquement")
        #expect(TopicSource.forum(CategoryID.privateMessages, title: "Jeux Video").navigationTitle == "Jeux Video")
    }
}

struct TopicFlagSpeechTests {
    @Test("A flag shown only as a tint is spoken: the dense row's icon labels")
    func flagLabels() {
        #expect(TopicRowCues.flagLabel(.yellow) == "Favori")
        #expect(TopicRowCues.flagLabel(.blue) == "Drapeau")
        #expect(TopicRowCues.flagLabel(.red) == "Lu")
        #expect(TopicRowCues.flagLabel(nil) == nil)
    }
}
