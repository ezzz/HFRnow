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

    @Test(arguments: [
        "superblue", "redface3dbig", "redface", "redface-blue", "blue", "white", "classic", "classic-red", "beta"
    ])
    func aShippedOptionKeepsItsRawValueNameAndPack(raw: String) {
        let names = [
            "superblue": "", "redface3dbig": "Icon-RedFace3DBig", "redface": "Icon-REDFACE", "redface-blue": "Icon-REDFACEBLUE",
            "blue": "Icon-BLUE", "white": "Icon-WHITE", "classic": "Icon-CLASSIC", "classic-red": "Icon-CLASSIC-RED", "beta": "Icon-BETA"
        ]
        let option = AppIconOption(rawValue: raw)
        #expect(option?.alternateIconName ?? "" == names[raw])
        #expect(option?.pack == (raw == "beta" ? .beta : .legacy))
        #expect(option?.window == nil)
    }

    @Test func everyAlternateIconNameIsInTheBuiltInfoPlist() {
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let alternates = Set((icons?["CFBundleAlternateIcons"] as? [String: Any])?.keys.map { $0 } ?? [])
        for option in AppIconOption.allCases {
            guard let name = option.alternateIconName else { continue }
            #expect(alternates.contains(name), "\(name) is missing from ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES")
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

    @Test func theLot190IconsHaveTheirRawValueNamePackAndWindow() {
        let expected: [(String, String, AppIconPack, Bool)] = [
            ("classic-blue", "Icon-CLASSIC-BLUE", .legacy, false), ("orange", "Icon-ORANGE", .legacy, false),
            ("beta-red", "Icon-BETA-RED", .beta, false), ("xface", "Icon-XFACE", .xface, false),
            ("xface-pride", "Icon-XFACE-PRIDE", .xface, false), ("xface-pride-outline", "Icon-XFACE-PRIDE-OUTLINE", .xface, false),
            ("xface-gradient-light", "Icon-XFACE-GRADIENT-LIGHT", .xface, false),
            ("xface-gradient-dark", "Icon-XFACE-GRADIENT-DARK", .xface, false), ("xface-gold", "Icon-XFACE-GOLD", .xface, false),
            ("xface-gold-on-black", "Icon-XFACE-GOLD-ON-BLACK", .xface, false),
            ("xface-gold-outline", "Icon-XFACE-GOLD-OUTLINE", .xface, false), ("xface-5250", "Icon-XFACE-5250", .xface, false),
            ("xface-negative", "Icon-XFACE-NEGATIVE", .xface, false),
            ("xface-negative-inverted", "Icon-XFACE-NEGATIVE-INVERTED", .xface, false),
            ("xface-sunset", "Icon-XFACE-SUNSET", .xface, false),
            ("halloween-jack", "Icon-HALLOWEEN-JACK", .season, true), ("halloween-hfr", "Icon-HALLOWEEN-HFR", .season, true),
            ("spring", "Icon-SPRING", .season, false), ("summer", "Icon-SUMMER", .season, false), ("winter", "Icon-WINTER", .season, false)
        ]
        #expect(expected.count == 20)
        for (raw, name, pack, dated) in expected {
            let option = AppIconOption(rawValue: raw)
            #expect(option?.alternateIconName == name, "\(raw)")
            #expect(option?.pack == pack, "\(raw)")
            #expect((option?.window != nil) == dated, "\(raw)")
        }
    }

    @Test func halloweenIconsAreOfferedOnlyInOctober() {
        #expect(offered(on: IconTestCalendar.date(2026, 9, 30)).isDisjoint(with: [.halloweenJack, .halloweenHfr]))
        #expect(offered(on: IconTestCalendar.date(2026, 10, 1)).isSuperset(of: [.halloweenJack, .halloweenHfr]))
        #expect(offered(on: IconTestCalendar.date(2026, 10, 31)).isSuperset(of: [.halloweenJack, .halloweenHfr]))
        #expect(offered(on: IconTestCalendar.date(2026, 11, 1)).isDisjoint(with: [.halloweenJack, .halloweenHfr]))
    }

    @Test func everyAlternateIconOfTheBuildHasAnOptionWithAPack() {
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let alternates = Set((icons?["CFBundleAlternateIcons"] as? [String: Any])?.keys.map { $0 } ?? [])
        let optionNames = Set(AppIconOption.allCases.compactMap(\.alternateIconName))
        #expect(!alternates.isEmpty)
        let extra = alternates.subtracting(optionNames)
        let missing = optionNames.subtracting(alternates)
        #expect(alternates == optionNames, "unregistered: \(extra), unbuilt: \(missing)")
    }

    /// The sources sit next to the tests in the checkout CI builds from; skipped when the tests run without it.
    @Test func everyOptionHasItsIconBundleInTheSources() throws {
        let appDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "SwiftHFR")
        try #require(FileManager.default.fileExists(atPath: appDirectory.appending(path: "Settings").path), "sources not found")
        for option in AppIconOption.allCases {
            let manifest = appDirectory.appending(path: "\(option.iconBundleName).icon").appending(path: "icon.json")
            #expect(FileManager.default.fileExists(atPath: manifest.path), "no \(option.iconBundleName).icon")
        }
    }

    @Test func sectionsFollowThePackOrderAndOmitEmptyPacks() {
        let packs = model(on: IconTestCalendar.date(2026, 12, 10)).sections.map(\.pack)
        #expect(packs == [.legacy, .beta, .xface, .season])
        #expect(model(on: IconTestCalendar.date(2026, 6, 10)).sections.map(\.pack) == [.legacy, .beta, .xface, .season])
    }

    @Test func everyOptionBelongsToExactlyOneSectionWhenItsWindowIsOpen() {
        let sections = model(on: IconTestCalendar.date(2026, 12, 10)).sections
        let day = IconTestCalendar.date(2026, 12, 10)
        let closed = AppIconOption.allCases.filter { !$0.isOffered(on: day, calendar: calendar) }
        #expect(sections.flatMap(\.options).count == AppIconOption.allCases.count - closed.count)
        #expect(Set(sections.flatMap(\.options)).count == sections.flatMap(\.options).count)
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
