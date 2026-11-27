import HFRStorage
import UIKit

// Port of HFRswift/Swift/Common.swift (AppHaptics, lines 50-85) and SuperHFRplus/Helpers/UIImpactFeedbackGenerator+UserDefaults.m
// @ 2440d79. Differences: the store and the generator are injected; only impacts are played (legacy's notification haptics have no
// call site, #1196).
/// Every haptic of the app goes through here, so the "Retours haptiques" setting (`haptics`, default on) governs all of them.
@MainActor
struct HapticFeedback {
    /// What to play.
    enum Kind: Equatable {
        case impact(UIImpactFeedbackGenerator.FeedbackStyle)
    }

    private let store: any SettingsStore
    private let perform: @MainActor (Kind) -> Void

    /// `perform` plays the feedback; the default drives the UIKit generators.
    init(store: any SettingsStore, perform: @escaping @MainActor (Kind) -> Void = HapticFeedback.play) {
        self.store = store
        self.perform = perform
    }

    /// The app's haptics, on the user defaults store.
    static let live = HapticFeedback(store: UserDefaultsSettingsStore())

    /// The setting, read at each call (legacy `AppHaptics.isEnabled`).
    var isEnabled: Bool { store.value(for: SettingKey.haptics) }

    /// A physical impact, unless haptics are off.
    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else { return }
        perform(.impact(style))
    }

    /// The UIKit generators; the default `perform`.
    static func play(_ kind: Kind) {
        switch kind {
        case .impact(let style):
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        }
    }
}
