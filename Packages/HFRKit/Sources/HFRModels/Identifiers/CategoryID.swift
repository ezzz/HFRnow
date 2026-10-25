/// A forum category as HFR names it in the `cat` query parameter: a number, or `prive` for private messages.
public enum CategoryID: Sendable, Hashable, Codable {
    /// A public forum category, e.g. `13` for "Discussions".
    case forum(Int)
    /// The private messages pseudo-category (`cat=prive`).
    case privateMessages

    /// Wire value of the private messages category.
    private static let privateQueryValue = "prive"

    /// Parses a `cat` query value; returns nil for anything that is neither `prive` nor a non-negative decimal number.
    public init?(queryValue: String) {
        if queryValue == Self.privateQueryValue {
            self = .privateMessages
        } else if !queryValue.isEmpty, queryValue.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int(queryValue) {
            self = .forum(number)
        } else {
            return nil
        }
    }

    /// The value HFR expects in the `cat` query parameter.
    public var queryValue: String {
        switch self {
        case .forum(let number): String(number)
        case .privateMessages: Self.privateQueryValue
        }
    }

    /// Decodes from the same string HFR uses in URLs, so persisted data stays readable.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let category = Self(queryValue: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid HFR category id: \(value)")
        }
        self = category
    }

    /// Encodes as the `cat` query value.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(queryValue)
    }
}
