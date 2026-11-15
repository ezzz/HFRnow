import Foundation
import HFRStorage
@testable import SwiftHFR
import Testing

@MainActor @Suite(.timeLimit(.minutes(5)))
struct AppIconSeasonModelTests {
    private let calendar = IconTestCalendar.calendar

    private func season(
        _ store: InMemorySettingsStore, _ switcher: FakeIconSwitcher, on date: Date
    ) -> AppIconSeasonModel {
        AppIconSeasonModel(store: store, switcher: switcher, calendar: calendar, now: { date })
    }

    @Test func noQuestionWhileTheDatedIconIsInsideItsWindow() {
        let store = InMemorySettingsStore(["icon": .string("noel-hfr"), "icon_previous": .string("blue")])
        let model = season(store, FakeIconSwitcher(current: "Icon-NOEL-HFR"), on: IconTestCalendar.date(2026, 12, 26))
        model.checkAtLaunch()
        #expect(model.question == nil)
    }

    @Test func theQuestionComesOnTheFirstLaunchAfterTheWindow() {
        let store = InMemorySettingsStore(["icon": .string("noel-hfr"), "icon_previous": .string("blue")])
        let model = season(store, FakeIconSwitcher(current: "Icon-NOEL-HFR"), on: IconTestCalendar.date(2026, 12, 27))
        model.checkAtLaunch()
        #expect(model.question?.dated == .noelHfr)
        #expect(model.question?.previous == .blue)
    }

    @Test func noQuestionWhenNoDatedIconIsActive() {
        let store = InMemorySettingsStore(["icon": .string("blue")])
        let model = season(store, FakeIconSwitcher(current: "Icon-BLUE"), on: IconTestCalendar.date(2027, 1, 10))
        model.checkAtLaunch()
        #expect(model.question == nil)
    }

    @Test func keepingTheIconAsksNeverAgainThatSeasonButAgainTheNextOne() {
        let store = InMemorySettingsStore(["icon": .string("noel-hfr"), "icon_previous": .string("blue")])
        let switcher = FakeIconSwitcher(current: "Icon-NOEL-HFR")
        let first = season(store, switcher, on: IconTestCalendar.date(2026, 12, 27))
        first.checkAtLaunch()
        first.keep()
        #expect(first.question == nil)
        #expect(switcher.applied.isEmpty)
        // Next launches, including after New Year's Day: the same window, already answered.
        for date in [IconTestCalendar.date(2026, 12, 28), IconTestCalendar.date(2027, 1, 3), IconTestCalendar.date(2027, 6, 1)] {
            let again = season(store, switcher, on: date)
            again.checkAtLaunch()
            #expect(again.question == nil)
        }
        // A year later, the icon is still there: the new season's end asks again.
        let nextYear = season(store, switcher, on: IconTestCalendar.date(2027, 12, 27))
        nextYear.checkAtLaunch()
        #expect(nextYear.question != nil)
    }

    @Test func answeringYesAppliesThePreviousIconStoresItAndAsksNoMore() async {
        let store = InMemorySettingsStore(["icon": .string("noel-hfr"), "icon_previous": .string("blue")])
        let switcher = FakeIconSwitcher(current: "Icon-NOEL-HFR")
        let model = season(store, switcher, on: IconTestCalendar.date(2027, 1, 2))
        model.checkAtLaunch()
        await model.revert()
        #expect(switcher.applied == ["Icon-BLUE"])
        #expect(store.rawValue(forKey: "icon") == .string("blue"))
        #expect(store.rawValue(forKey: "icon_previous") == nil)
        #expect(model.question == nil)
        let again = season(store, switcher, on: IconTestCalendar.date(2027, 1, 3))
        again.checkAtLaunch()
        #expect(again.question == nil)
    }

    @Test func withoutARememberedIconYesGoesBackToTheDefault() async {
        let store = InMemorySettingsStore(["icon": .string("noel-redface")])
        let switcher = FakeIconSwitcher(current: "Icon-NOEL-REDFACE")
        let model = season(store, switcher, on: IconTestCalendar.date(2027, 3, 1))
        model.checkAtLaunch()
        #expect(model.question?.previous == .superblue)
        await model.revert()
        #expect(switcher.applied == [nil])
    }

    @Test func aRefusedRevertKeepsTheIconAndAsksAgainNextLaunch() async {
        let store = InMemorySettingsStore(["icon": .string("noel-hfr"), "icon_previous": .string("blue")])
        let switcher = FakeIconSwitcher(current: "Icon-NOEL-HFR")
        switcher.fails = true
        let model = season(store, switcher, on: IconTestCalendar.date(2027, 1, 2))
        model.checkAtLaunch()
        await model.revert()
        #expect(model.question == nil)
        #expect(model.errorMessage?.hasPrefix("Impossible de changer l’icône") == true)
        #expect(store.rawValue(forKey: "icon") == .string("noel-hfr"))
        let again = season(store, switcher, on: IconTestCalendar.date(2027, 1, 3))
        again.checkAtLaunch()
        #expect(again.question != nil)
    }

    @Test func noQuestionWhereAlternateIconsAreUnsupported() {
        let store = InMemorySettingsStore(["icon": .string("noel-hfr")])
        let switcher = FakeIconSwitcher(current: nil)
        switcher.supportsAlternateIcons = false
        let model = season(store, switcher, on: IconTestCalendar.date(2027, 1, 2))
        model.checkAtLaunch()
        #expect(model.question == nil)
    }
}
