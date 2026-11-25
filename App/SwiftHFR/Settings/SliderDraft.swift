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

    /// The slider moved to `value`. Returns the value to save now, nil while dragging.
    mutating func move(to value: Value) -> Value? {
        guard isEditing else { return value }
        draft = value
        return nil
    }

    /// The drag started or ended. Returns the value to save when it ended on a draft, nil otherwise.
    mutating func editingChanged(_ editing: Bool) -> Value? {
        isEditing = editing
        let final = editing ? nil : draft
        draft = nil
        return final
    }
}
