/// The `type` of an `<input>` of an HFR form; unknown types map to `.other`.
public enum FormInputKind: String, Sendable, Codable {
    /// Plain text input (also the default when `type` is absent).
    case text
    /// Hidden input.
    case hidden
    /// Checkbox.
    case checkbox
    /// Radio button.
    case radio
    /// Submit button.
    case submit
    /// Password input.
    case password
    /// Any other input type.
    case other

    /// Maps an HTML `type` attribute (case-insensitive, nil or empty means text) to a kind.
    public init(htmlType: String?) {
        let value = htmlType?.lowercased() ?? ""
        self = value.isEmpty ? .text : (Self(rawValue: value) ?? .other)
    }
}
