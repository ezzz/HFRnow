import CoreGraphics
import Foundation
import HFRStorage
@testable import SwiftHFR

/// A clock the tests move by hand: no real waiting (LOT-166).
@MainActor
final class SeasonTestClock {
    var now: Date
    var reduceMotion = false
    /// The device's time zone, which the user may change during a run.
    var timeZone = SeasonTestClock.calendar.timeZone

    init(_ day: Int, _ month: Int, _ year: Int, hour: Int = 10, minute: Int = 0) {
        now = Self.date(day, month, year, hour: hour, minute: minute)
    }

    func move(to day: Int, _ month: Int, _ year: Int, hour: Int = 10) {
        now = Self.date(day, month, year, hour: hour)
    }

    /// Local dates: the window follows the user's calendar, so the tests use a non-UTC zone.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        return calendar
    }()

    static func date(_ day: Int, _ month: Int, _ year: Int, hour: Int = 10, minute: Int = 0) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return calendar.date(from: components) ?? .distantPast
    }

    /// A model on `store` reading this clock, as the app builds it at each launch.
    func model(store: any SettingsStore) -> SeasonalThemeModel {
        // Crossings on this clock, with silent haptics and reproducible paths.
        let crossings = NoelCrossingModel(
            now: { self.now }, random: SeededRandom(1), haptics: HapticFeedback(store: InMemorySettingsStore()) { _ in }
        )
        return SeasonalThemeModel(
            store: store, now: { self.now }, timeZone: { self.timeZone }, reduceMotion: { self.reduceMotion }, crossings: crossings
        )
    }
}

extension SeasonalThemeModel {
    /// Plays the arrival sleigh to its end, as a scene's layer does, so the alert may come.
    func playArrivalSleigh() {
        crossings.foregroundChanged(active: true)
        if let sleigh = crossings.crossing(
            for: UUID(), area: CGSize(width: 402, height: 650), windowHeight: 874, screen: ScreenState(),
            animationsAllowed: animationsAllowed, crossingsOn: false
        ) {
            crossings.finish(sleigh.id)
        }
    }
}

/// Random numbers the tests choose: `values` in turn, then again from the start.
@MainActor
final class ScriptedRandom: SeasonalRandom {
    private let values: [Double]
    private var index = 0

    init(_ values: [Double]) { self.values = values.isEmpty ? [0] : values }

    func unit() -> Double {
        defer { index = (index + 1) % values.count }
        return values[index]
    }
}

/// A reproducible spread of random numbers (a 64-bit LCG), for properties checked over many paths.
@MainActor
final class SeededRandom: SeasonalRandom {
    private var state: UInt64

    init(_ seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }

    func unit() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}

/// The haptics a crossing played, through `HapticFeedback` like the app's `.live`.
@MainActor
final class HapticRecorder {
    var played: [HapticFeedback.Kind] = []

    func feedback(store: InMemorySettingsStore = InMemorySettingsStore()) -> HapticFeedback {
        HapticFeedback(store: store) { self.played.append($0) }
    }
}
