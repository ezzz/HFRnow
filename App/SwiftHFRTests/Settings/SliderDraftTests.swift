import HFRStorage
@testable import SwiftHFR
import Testing

/// #1211: a drag saves once, on release; a change outside a drag (VoiceOver) saves each step.
@MainActor
struct SliderDraftTests {
    @Test func aDragWritesTheStoreOnceOnRelease() {
        let store = CountingStore()
        let model = ThemeSettingsModel(store: store)
        var draft = SliderDraft<Double>()
        func save(_ value: Double?) { if let value { model.darkBrightness = value } }

        save(draft.editingChanged(true))
        for tick in 1...199 { save(draft.move(to: 0.3 + Double(tick) * 0.001)) }
        save(draft.move(to: 0.5))
        #expect(store.writes == 0)
        #expect(draft.shown(saved: model.darkBrightness) == 0.5)
        #expect(model.darkBrightness == 1)

        save(draft.editingChanged(false))
        #expect(store.writes == 1)
        #expect(model.darkBrightness == 0.5)
        #expect(draft.shown(saved: model.darkBrightness) == 0.5)
    }

    @Test func aTapWithoutMovementSavesNothing() {
        var draft = SliderDraft<Double>()
        #expect(draft.editingChanged(true) == nil)
        #expect(draft.editingChanged(false) == nil)
    }

    @Test func eachStepOutsideADragIsSavedAtOnce() {
        var draft = SliderDraft<Int>()
        #expect(draft.move(to: 101) == 101)
        #expect(draft.move(to: 102) == 102)
        #expect(draft.draft == nil)
    }
}

/// Counts the writes a model makes.
private final class CountingStore: SettingsStore, @unchecked Sendable {
    private let base = InMemorySettingsStore()
    private(set) var writes = 0
    func rawValue(forKey key: String) -> SettingRawValue? { base.rawValue(forKey: key) }
    func setRawValue(_ value: SettingRawValue, forKey key: String) { writes += 1; base.setRawValue(value, forKey: key) }
    func removeValue(forKey key: String) { writes += 1; base.removeValue(forKey: key) }
}
