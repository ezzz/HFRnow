import SwiftUI

/// What a settings slider shows and saves (#1211): while the finger is down the value lives in a draft that only the slider's own
/// screen reads, and the model, so the store, iCloud and every screen behind, gets the final value once, on release. Without it
/// each tick of a 1,000-step slider wrote the store and rebuilt the app root. A change made while not dragging (VoiceOver's
/// increment and decrement, which end no gesture) is saved at once, so each step still counts.
struct SliderDraft<Value: Equatable> {
    /// The value being dragged; nil when no drag moved the slider.
    private(set) var draft: Value?
    private(set) var isEditing = false

    /// The value the slider and its readout show: the draft while dragging, else what is saved.
    func shown(saved: Value) -> Value { draft ?? saved }

    /// The slider moved to `value`: kept as the draft while dragging, else `save` runs at once.
    mutating func move(to value: Value, save: (Value) -> Void) {
        guard isEditing else { return save(value) }
        draft = value
    }

    /// The drag started or ended: on its end `save` runs once with the dragged value, if the slider moved. A row that disappears
    /// mid-drag may never get the end, and the dragged value is then dropped.
    mutating func editingChanged(_ editing: Bool, save: (Value) -> Void) {
        isEditing = editing
        let final = editing ? nil : draft
        draft = nil
        if let final { save(final) }
    }
}

/// A `Slider` that follows `draft` while dragged and calls `save` once on release (#1211), the one place the three Réglages sliders
/// share their wiring. The caller owns `draft` to read the shown value (readout, tint, previews).
struct DraftSlider: View {
    @Binding var draft: SliderDraft<Double>
    /// The saved value the slider shows when no drag is on.
    let saved: Double
    let range: ClosedRange<Double>
    let step: Double
    let save: (Double) -> Void

    var body: some View {
        Slider(
            value: Binding(get: { draft.shown(saved: saved) }, set: { draft.move(to: $0, save: save) }),
            in: range, step: step,
            onEditingChanged: { draft.editingChanged($0, save: save) }
        )
    }
}
