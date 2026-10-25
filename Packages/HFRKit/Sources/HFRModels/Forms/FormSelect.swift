/// A `<select>` of a form.
public struct FormSelect: Sendable, Hashable, Codable {
    /// The `name` attribute.
    public var name: String
    /// Options in page order.
    public var options: [FormOption]
    /// Value of the option marked `selected`, nil when none is.
    public var selectedValue: String?

    /// What a browser would send: the selected option, else the first one; nil when there are no options.
    public var effectiveValue: String? {
        selectedValue ?? options.first?.value
    }

    /// Creates a select.
    public init(name: String, options: [FormOption] = [], selectedValue: String? = nil) {
        self.name = name
        self.options = options
        self.selectedValue = selectedValue
    }
}
