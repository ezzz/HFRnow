/// An `<input>` of a form, as found in the page (decisions about what to send are made later).
public struct FormField: Sendable, Hashable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The `name` attribute.
    public var name: String
    /// The `value` attribute, entity-decoded; empty when absent.
    public var value: String
    /// Input type.
    public var kind: FormInputKind
    /// True when a checkbox or radio carries the `checked` attribute.
    public var isChecked: Bool

    /// Creates a field.
    public init(name: String, value: String = "", kind: FormInputKind = .text, isChecked: Bool = false) {
        self.name = name
        self.value = value
        self.kind = kind
        self.isChecked = isChecked
    }

    /// Hidden and password values hold tokens (`hash_check`) or secrets, so diagnostics never print them.
    private var displayedValue: String {
        kind == .hidden || kind == .password ? "<redacted>" : value
    }

    /// Summary that redacts hidden and password values.
    public var description: String {
        "FormField(\(name), \(kind.rawValue), value: \(displayedValue), checked: \(isChecked))"
    }

    /// Same as `description`.
    public var debugDescription: String { description }

    /// Reflection (`dump`, debugger) redacts the value too.
    public var customMirror: Mirror {
        Mirror(self, children: [
            "name": name, "value": displayedValue, "kind": kind, "isChecked": isChecked
        ], displayStyle: .struct)
    }
}
