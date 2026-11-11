import HFRStorage
@testable import SwiftHFR
import Testing
import UIKit

@MainActor @Suite(.timeLimit(.minutes(5)))
struct AppIconPackTests {
    private let calendar = IconTestCalendar.calendar

    private func model(
        _ store: InMemorySettingsStore = InMemorySettingsStore(), current: String? = nil, on date: Date
    ) -> AppIconSettingsModel {
        AppIconSettingsModel(store: store, switcher: FakeIconSwitcher(current: current), calendar: calendar, now: { date })
    }

    private func offered(on date: Date) -> Set<AppIconOption> {
        Set(model(on: date).sections.flatMap(\.options))
    }

    // MARK: Packs

    @Test func theShippedOptionsKeepTheirRawValuesAndNamesAndLiveInLegacyOrBeta() {
        let shipped: [(String, String?, AppIconPack)] = [
            ("superblue", nil, .legacy), ("redface3dbig", "Icon-RedFace3DBig", .legacy), ("redface", "Icon-REDFACE", .legacy),
            ("redface-blue", "Icon-REDFACEBLUE", .legacy), ("blue", "Icon-BLUE", .legacy), ("white", "Icon-WHITE", .legacy),
            ("classic", "Icon-CLASSIC", .legacy), ("classic-red", "Icon-CLASSIC-RED", .legacy), ("beta", "Icon-BETA", .beta)
        ]
        for (raw, name, pack) in shipped {
            let option = AppIconOption(rawValue: raw)
            #expect(option?.alternateIconName == name)
            #expect(option?.pack == pack)
            #expect(option?.window == nil)
        }
    }

    @Test func theNoelIconsAreInTheSeasonPackWithTheirNames() {
        #expect(AppIconOption.noelRedface.rawValue == "noel-redface")
        #expect(AppIconOption.noelRedface.alternateIconName == "Icon-NOEL-REDFACE")
        #expect(AppIconOption.noelHfr.rawValue == "noel-hfr")
        #expect(AppIconOption.noelHfr.alternateIconName == "Icon-NOEL-HFR")
        #expect(AppIconOption.noelRedface.pack == .season)
        #expect(AppIconOption.noelHfr.pack == .season)
    }

    @Test func sectionsFollowThePackOrderAndOmitEmptyPacks() {
        let packs = model(on: IconTestCalendar.date(2026, 12, 10)).sections.map(\.pack)
        #expect(packs == [.legacy, .beta, .season])
        #expect(model(on: IconTestCalendar.date(2026, 6, 10)).sections.map(\.pack) == [.legacy, .beta])
    }

    @Test func everyOptionBelongsToExactlyOneSectionWhenAllAreOffered() {
        let sections = model(on: IconTestCalendar.date(2026, 12, 10)).sections
        #expect(sections.flatMap(\.options).count == AppIconOption.allCases.count)
    }

    // MARK: Windows (Noël, 01/12 to 26/12 inclusive)

    @Test(arguments: [
        (2026, 11, 30, false), (2026, 12, 1, true), (2026, 12, 15, true), (2026, 12, 26, true), (2026, 12, 27, false), (2027, 1, 5, false)
    ])
    func theNoelIconsAreOfferedOnlyInsideTheirWindow(year: Int, month: Int, day: Int, shown: Bool) {
        let options = offered(on: IconTestCalendar.date(year, month, day))
        #expect(options.contains(.noelRedface) == shown)
        #expect(options.contains(.noelHfr) == shown)
    }

    @Test func theLastSecondsOfThe26thAreStillInsideTheWindow() {
        #expect(AppIconOption.noelHfr.window?.contains(IconTestCalendar.date(2026, 12, 26, hour: 23), calendar: calendar) == true)
        #expect(AppIconOption.noelHfr.window?.contains(IconTestCalendar.date(2026, 12, 27, hour: 0), calendar: calendar) == false)
    }

    @Test func aWindowThatWrapsTheYearCoversBothEnds() {
        let window = IconWindow(startMonth: 12, startDay: 20, endMonth: 1, endDay: 5)
        #expect(window.contains(IconTestCalendar.date(2026, 12, 25), calendar: calendar))
        #expect(window.contains(IconTestCalendar.date(2027, 1, 5), calendar: calendar))
        #expect(!window.contains(IconTestCalendar.date(2027, 1, 6), calendar: calendar))
        #expect(!window.contains(IconTestCalendar.date(2026, 12, 19), calendar: calendar))
    }

    @Test func aDatedIconOutsideItsWindowCannotBeChosen() async {
        let switcher = FakeIconSwitcher()
        let model = AppIconSettingsModel(
            store: InMemorySettingsStore(), switcher: switcher, calendar: calendar, now: { IconTestCalendar.date(2026, 11, 30) }
        )
        await model.select(.noelHfr)
        #expect(switcher.applied.isEmpty)
        #expect(model.selection == .superblue)
    }

    @Test func aDatedIconInsideItsWindowCanBeChosen() async {
        let switcher = FakeIconSwitcher()
        let store = InMemorySettingsStore()
        let model = AppIconSettingsModel(store: store, switcher: switcher, calendar: calendar, now: { IconTestCalendar.date(2026, 12, 1) })
        await model.select(.noelHfr)
        #expect(switcher.applied == ["Icon-NOEL-HFR"])
        #expect(store.rawValue(forKey: "icon") == .string("noel-hfr"))
    }

    @Test func theActiveDatedIconStaysListedAfterItsWindowSoTheRingShowsWhereTheUserIs() {
        let model = model(current: "Icon-NOEL-HFR", on: IconTestCalendar.date(2027, 1, 3))
        #expect(model.selection == .noelHfr)
        let options = model.sections.flatMap(\.options)
        #expect(options.contains(.noelHfr))
        #expect(!options.contains(.noelRedface))
    }

    // MARK: Previous icon

    @Test func choosingADatedIconRemembersTheIconItReplacesOnlyOnce() async {
        let store = InMemorySettingsStore()
        let model = AppIconSettingsModel(
            store: store, switcher: FakeIconSwitcher(current: "Icon-BLUE"), calendar: calendar, now: { IconTestCalendar.date(2026, 12, 2) }
        )
        await model.select(.noelRedface)
        #expect(store.rawValue(forKey: "icon_previous") == .string("blue"))
        await model.select(.noelHfr)
        #expect(store.rawValue(forKey: "icon_previous") == .string("blue"))
        await model.select(.white)
        #expect(store.rawValue(forKey: "icon_previous") == nil)
    }

    // MARK: Previews

    @Test func everyOptionHasAPreviewImageInTheAppCatalogue() {
        for option in AppIconOption.allCases {
            #expect(UIImage(named: option.previewImageName) != nil, "no preview image \(option.previewImageName)")
        }
    }

    @Test func thePreviewNameFollowsTheIconBundleName() {
        #expect(AppIconOption.superblue.previewImageName == "IconPreview-Icon-RedFace3D")
        #expect(AppIconOption.noelHfr.previewImageName == "IconPreview-Icon-NOEL-HFR")
        #expect(AppIconOption.classicRed.previewImageName == "IconPreview-Icon-CLASSIC-RED")
    }
}
