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
        // The same two calls the slider's binding and `onEditingChanged` make in the views.
        func move(_ value: Double) { draft.move(to: value) { model.darkBrightness = $0 } }
        func editing(_ on: Bool) { draft.editingChanged(on) { model.darkBrightness = $0 } }

        editing(true)
        for tick in 1...199 { move(0.3 + Double(tick) * 0.001) }
        move(0.5)
        #expect(store.writes == 0)
        #expect(draft.shown(saved: model.darkBrightness) == 0.5)
        #expect(model.darkBrightness == 1)

        editing(false)
        #expect(store.writes == 1)
        #expect(model.darkBrightness == 0.5)
        #expect(draft.shown(saved: model.darkBrightness) == 0.5)
    }

    @Test func aTapWithoutMovementSavesNothing() {
        var draft = SliderDraft<Double>()
        var saved: [Double] = []
        draft.editingChanged(true) { saved.append($0) }
        draft.editingChanged(false) { saved.append($0) }
        #expect(saved.isEmpty)
    }

    @Test func eachStepOutsideADragIsSavedAtOnce() {
        var draft = SliderDraft<Int>()
        var saved: [Int] = []
        draft.move(to: 101) { saved.append($0) }
        draft.move(to: 102) { saved.append($0) }
        #expect(saved == [101, 102])
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
