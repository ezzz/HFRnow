import HFRModels

/// The sub-category picker of a new topic (LOT-089): the form's options, the choice, and whether they are being read.
struct NewTopicSubcategories: Equatable, Sendable {
    /// Options in the form's order, empty until read.
    private(set) var options: [FormOption] = []
    /// The chosen option's `value` (`R45a`: the first, "Aucune", is `""`); nil until the form was read.
    private(set) var selected: String?
    /// The form is being read.
    private(set) var isLoading = false
    /// Why the list could not be read; the topic can still be sent (HFR's own default choice then applies).
    private(set) var warning: String?

    mutating func beginLoading() {
        isLoading = true
        warning = nil
    }

    /// Takes the form's options. A choice already made is kept when the form offers it again; otherwise the preselected
    /// option, else the first (`R45a`: none is selected, so "Aucune").
    mutating func apply(_ form: NewTopicOptions) {
        isLoading = false
        options = form.subcategories
        if let chosen = selected, form.subcategories.contains(where: { $0.value == chosen }) { return }
        selected = form.preselected
    }

    mutating func fail(_ message: String) {
        isLoading = false
        warning = message
    }

    /// Chooses `value` when the form offers it; returns whether it did.
    mutating func select(_ value: String) -> Bool {
        guard options.contains(where: { $0.value == value }) else { return false }
        selected = value
        return true
    }
}
