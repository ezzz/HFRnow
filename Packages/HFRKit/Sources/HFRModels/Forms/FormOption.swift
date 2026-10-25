/// An `<option>` of a form `<select>`.
public struct FormOption: Sendable, Hashable, Codable {
    /// The `value` attribute.
    public var value: String
    /// Visible label, entity-decoded.
    public var label: String

    /// Creates an option.
    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }
}
