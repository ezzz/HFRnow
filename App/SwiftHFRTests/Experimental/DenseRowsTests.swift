import Foundation
import HFRModels
import HFRStorage
import SwiftUI
@testable import SwiftHFR
import Testing

/// Réglages › Expérimental › « Lignes denses » (#903, #905, #973): the switch and the pure rules of the dense topic and MP rows.
@MainActor
struct DenseRowsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func topic(
        pages: Int = 5, flag: TopicFlag? = nil, current: Int? = nil, starter: String = "starter", last: LastPost? = nil
    ) -> TopicSummary {
        TopicSummary(
            title: "t", path: "/p", repliesCount: 9075, pageCount: pages, lastPost: last, starterOrInterlocutors: starter,
            flag: flag, flagPath: flag == nil ? nil : "/f", currentPage: current
        )
    }

    private func thread(
        group: Bool, starter: String = "membre", last: LastPost? = nil, replies: Int = 40, pages: Int = 3
    ) -> PrivateMessageThread {
        let summary = TopicSummary(
            topicID: TopicID(category: .privateMessages, topic: 3_207_033), title: "subject", path: "/p", repliesCount: replies,
            pageCount: pages, lastPost: last, starterOrInterlocutors: starter
        )
        return PrivateMessageThread(summary: summary, unreadBy: [], isUnreadByOthers: false, isGroup: group)
    }

    private func post(_ author: String, secondsAgo: Double?) -> LastPost {
        LastPost(author: author, path: "/m", date: secondsAgo.map { now.addingTimeInterval(-$0) })
    }

    // MARK: The switch

    @Test("The switch picks the dense row; off, or without settings in the environment, the legacy row")
    func theSwitchPicksTheRow() {
        let store = InMemorySettingsStore()
        let settings = ExperimentalSettings(store: store)
        #expect(TopicRowStyle.current(settings) == .legacy)
        #expect(TopicRowStyle.current(nil) == .legacy)
        settings.set(.denseRows, isOn: true)
        #expect(TopicRowStyle.current(settings) == .dense)
        #expect(ExperimentalSettings(store: store).isOn(.denseRows))
    }

    // MARK: Topic rows (#905)

    @Test("C: the last poster replaces the starter; D: no reply count")
    func lastPosterNoCount() {
        let row = topic(flag: .blue, current: 2, last: post("dernier", secondsAgo: 14 * 60))
        let line = DenseRowFormat.topicInfo(row, now: now)
        #expect(line == "⚑ 2 / 5 · dernier · 14 minutes")
        #expect(line?.contains("starter") == false)
        #expect(line?.contains("9075") == false && line?.contains("réponse") == false)
    }

    @Test("E: the age has no « il y a », in the units the operator listed")
    func ageWithoutIlYA() {
        func wide(_ seconds: Double) -> String { DenseRowFormat.age(of: now.addingTimeInterval(-seconds), now: now, style: .wide) }
        #expect(wide(20) == "1 minute")
        #expect(wide(14 * 60) == "14 minutes")
        #expect(wide(3 * 3600) == "3 heures")
        #expect(wide(2 * 86_400) == "2 jours")
        #expect(wide(14 * 86_400) == "2 semaines")
        #expect(wide(90 * 86_400) == "3 mois")
        #expect(wide(800 * 86_400) == "2 ans")
        #expect(wide(-60) == "1 minute")
        for seconds in [20.0, 840, 10_800, 1_209_600] { #expect(!wide(seconds).contains("il y a")) }
    }

    @Test("A topic without a flag page or without a last post still gives what is known")
    func partialTopics() {
        #expect(DenseRowFormat.topicInfo(topic(last: post("dernier", secondsAgo: 60)), now: now) == "dernier · 1 minute")
        #expect(DenseRowFormat.topicInfo(topic(flag: .red, current: 2), showsFlag: false, now: now) == nil)
        #expect(DenseRowFormat.topicInfo(topic(flag: .red, current: 2), now: now) == "⚑ 2 / 5")
        #expect(DenseRowFormat.topicInfo(topic(last: post("dernier", secondsAgo: nil)), now: now) == "dernier")
    }

    // MARK: MP rows (#973)

    @Test("A: no « Interlocuteurs multiples »; B: no reply count; C: « ⚑ x / y »; D: « 6 min » without « il y a »")
    func groupRow() {
        let group = thread(group: true, starter: "Interlocuteurs multiples", last: post("dernier", secondsAgo: 6 * 60))
        let line = DenseRowFormat.messageInfo(thread: group, flagLabel: "⚑ 2 / 3", now: now)
        #expect(line == "⚑ 2 / 3 · dernier · 6 min")
        #expect(line?.contains("multiples") == false && line?.contains("réponse") == false && line?.contains("il y a") == false)
        #expect(DenseRowFormat.messageInfo(thread: group, flagLabel: nil, now: now) == "dernier · 6 min")
    }

    @Test("A one-to-one row: the interlocutor, named once when they are the last poster; hours, then the date")
    func oneToOneRow() {
        let mine = thread(group: false, last: post("membre", secondsAgo: 2 * 3600))
        #expect(DenseRowFormat.messageInfo(thread: mine, flagLabel: nil, now: now) == "membre · 2 h")
        let theirs = thread(group: false, last: post("autre", secondsAgo: 3 * 86_400))
        #expect(DenseRowFormat.messageInfo(thread: theirs, flagLabel: nil, now: now) == "membre · autre · 12/01/2027")
        #expect(DenseRowFormat.messageInfo(thread: thread(group: false, starter: ""), flagLabel: nil, now: now) == nil)
    }

    // MARK: One line, bold sections (#905 E, F)

    @Test("E: one line, lifted only at accessibility sizes")
    func lineLimit() {
        #expect(DenseRowFormat.lineLimit(isAccessibilitySize: false) == 1)
        #expect(DenseRowFormat.lineLimit(isAccessibilitySize: true) == nil)
    }

    @Test("F: section titles are bold with the option on, and carry no weight at all with it off")
    func sectionTitleWeight() {
        let settings = ExperimentalSettings(store: InMemorySettingsStore())
        #expect(DenseRowFormat.titleWeight(settings) == nil)
        #expect(DenseRowFormat.titleWeight(nil) == nil)
        settings.set(.denseRows, isOn: true)
        #expect(DenseRowFormat.titleWeight(settings) == .bold)
    }

    @Test("The MP rows and the topic rows read the same switch")
    func oneSwitchForBothLists() {
        let settings = ExperimentalSettings(store: InMemorySettingsStore())
        #expect(!DenseRowFormat.isOn(settings) && !DenseRowFormat.isOn(nil))
        #expect(TopicRowStyle.current(settings) == .legacy)
        settings.set(.denseRows, isOn: true)
        #expect(DenseRowFormat.isOn(settings))
        #expect(TopicRowStyle.current(settings) == .dense)
    }

    // MARK: Markers kept from #903

    /// The marks are the ones the row showed before the move (`TopicRowView` @ dev-swift bfb855ef).
    @Test func theFlagMarksAreTheRowsOfBeforeTheMove() {
        #expect(DenseRowMarks.flagMark(.blue) == DenseRowMarks.FlagMark(symbol: "flag.fill", color: Color.blue, label: "Drapeau"))
        #expect(DenseRowMarks.flagMark(.red) == DenseRowMarks.FlagMark(symbol: "flag.fill", color: Color.red, label: "Lu"))
        #expect(DenseRowMarks.flagMark(.yellow) == DenseRowMarks.FlagMark(symbol: "star.fill", color: Color.yellow, label: "Favori"))
        #expect(DenseRowMarks.flagMark(nil) == nil)
    }
}
