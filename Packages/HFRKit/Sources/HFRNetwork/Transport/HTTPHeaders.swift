import Foundation
/// Case-insensitive HTTP header fields (names are stored lowercased).
public struct HTTPHeaders: Sendable, Equatable, ExpressibleByDictionaryLiteral {
    private var storage: [String: String]

    /// Creates headers from name/value pairs; a later duplicate (any case) wins.
    public init(_ fields: [String: String] = [:]) {
        storage = [:]
        for (name, value) in fields { storage[name.lowercased()] = value }
    }

    /// Creates headers from a dictionary literal.
    public init(dictionaryLiteral elements: (String, String)...) {
        storage = [:]
        for (name, value) in elements { storage[name.lowercased()] = value }
    }

    /// Reads or sets a header by case-insensitive name; setting `nil` removes it.
    public subscript(name: String) -> String? {
        get { storage[name.lowercased()] }
        set { storage[name.lowercased()] = newValue }
    }

    /// All fields keyed by lowercased name.
    public var fields: [String: String] { storage }
}
