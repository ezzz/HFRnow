import Foundation
/// Case-insensitive HTTP header fields (names are stored trimmed and lowercased, so ` Cookie` and `cookie` are one).
public struct HTTPHeaders: Sendable, Equatable, ExpressibleByDictionaryLiteral {
    private var storage: [String: String]

    /// Creates headers from name/value pairs; a later duplicate (any case) wins.
    public init(_ fields: [String: String] = [:]) {
        storage = [:]
        for (name, value) in fields { storage[Self.key(name)] = value }
    }

    /// Creates headers from a dictionary literal.
    public init(dictionaryLiteral elements: (String, String)...) {
        storage = [:]
        for (name, value) in elements { storage[Self.key(name)] = value }
    }

    /// Reads or sets a header by case-insensitive name; setting `nil` removes it.
    public subscript(name: String) -> String? {
        get { storage[Self.key(name)] }
        set { storage[Self.key(name)] = newValue }
    }

    /// All fields keyed by trimmed, lowercased name.
    public var fields: [String: String] { storage }

    /// Storage key of a header name: surrounding whitespace removed, lowercased.
    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
