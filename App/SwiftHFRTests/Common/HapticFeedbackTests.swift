import HFRStorage
@testable import SwiftHFR
import Testing

@MainActor
struct HapticFeedbackTests {
    private final class Recorder {
        var played: [HapticFeedback.Kind] = []
    }

    private func make(_ store: InMemorySettingsStore, _ recorder: Recorder) -> HapticFeedback {
        HapticFeedback(store: store) { recorder.played.append($0) }
    }

    @Test func hapticsAreOnByDefault() {
        let recorder = Recorder()
        let haptics = make(InMemorySettingsStore(), recorder)
        haptics.impact(.light)
        haptics.notification(.success)
        #expect(recorder.played == [.impact(.light), .notification(.success)])
    }

    @Test func offSilencesEveryKind() {
        let recorder = Recorder()
        let haptics = make(InMemorySettingsStore(["haptics": .bool(false)]), recorder)
        haptics.impact(.rigid)
        haptics.notification(.error)
        #expect(recorder.played.isEmpty)
    }

    @Test func theSettingIsReadAtEachCallAndTheModelWritesTheLegacyKey() {
        let store = InMemorySettingsStore()
        let recorder = Recorder()
        let haptics = make(store, recorder)
        let model = GeneralSettingsModel(store: store)
        model.hapticsEnabled = false
        haptics.impact(.light)
        #expect(recorder.played.isEmpty)
        #expect(store.rawValue(forKey: "haptics") == .bool(false))
        model.hapticsEnabled = true
        haptics.impact(.light)
        #expect(recorder.played == [.impact(.light)])
    }

    @Test func aLegacyStringValueIsHonoured() {
        let recorder = Recorder()
        make(InMemorySettingsStore(["haptics": .string("off")]), recorder).impact(.light)
        #expect(recorder.played.isEmpty)
    }
}
