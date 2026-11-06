/// Decodes `Decodable` values from a `JSONValue` tree read by `JSONTokenizer`, with `JSONDecoder`'s conversions: a
/// number decodes as an integer when its value is one (`1.0`, `1e2`), never from a string; a string never from a number.
///
/// A `JSONValue` is taken whole (its `init(from:)` reads `value`), so the unmodelled parts keep their numbers' text.
final class JSONTreeDecoder: Decoder {
    /// The value being decoded.
    let value: JSONValue
    let codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    init(_ value: JSONValue, codingPath: [any CodingKey] = []) {
        self.value = value
        self.codingPath = codingPath
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .object(let members) = value else {
            throw Self.mismatch([String: JSONValue].self, found: value, path: codingPath)
        }
        return KeyedDecodingContainer(Keyed(members: members, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard case .array(let items) = value else { throw Self.mismatch([JSONValue].self, found: value, path: codingPath) }
        return Unkeyed(items: items, codingPath: codingPath)
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        Single(value: value, codingPath: codingPath)
    }

    /// `valueNotFound` for `null`, `typeMismatch` for another kind of value, as `JSONDecoder` reports them.
    static func mismatch(_ type: Any.Type, found value: JSONValue, path: [any CodingKey]) -> DecodingError {
        if value == .null {
            return .valueNotFound(type, .init(codingPath: path, debugDescription: "Expected \(type) value but found null instead."))
        }
        let found = switch value {
        case .null: "null"
        case .bool: "a boolean"
        case .number: "a number"
        case .string: "a string"
        case .array: "an array"
        case .object: "a dictionary"
        }
        let context = DecodingError.Context(codingPath: path, debugDescription: "Expected to decode \(type) but found \(found) instead.")
        return .typeMismatch(type, context)
    }

    // MARK: - Containers

    private struct Single: SingleValueDecodingContainer {
        let value: JSONValue
        let codingPath: [any CodingKey]

        func decodeNil() -> Bool { value == .null }

        func decode(_ type: Bool.Type) throws -> Bool {
            guard case .bool(let flag) = value else {
                // `JSONDecoder` reports `null` as a type mismatch for `Bool` alone (`valueNotFound` for the other types).
                guard value == .null else { throw JSONTreeDecoder.mismatch(type, found: value, path: codingPath) }
                let context = DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Bool but found null instead.")
                throw DecodingError.typeMismatch(type, context)
            }
            return flag
        }

        func decode(_ type: String.Type) throws -> String {
            guard case .string(let text) = value else { throw JSONTreeDecoder.mismatch(type, found: value, path: codingPath) }
            return text
        }

        func decode(_ type: Double.Type) throws -> Double { try floatingPoint { Double($0) } }
        func decode(_ type: Float.Type) throws -> Float { try floatingPoint { Float($0) } }
        func decode(_ type: Int.Type) throws -> Int { try integer() }
        func decode(_ type: Int8.Type) throws -> Int8 { try integer() }
        func decode(_ type: Int16.Type) throws -> Int16 { try integer() }
        func decode(_ type: Int32.Type) throws -> Int32 { try integer() }
        func decode(_ type: Int64.Type) throws -> Int64 { try integer() }
        func decode(_ type: UInt.Type) throws -> UInt { try integer() }
        func decode(_ type: UInt8.Type) throws -> UInt8 { try integer() }
        func decode(_ type: UInt16.Type) throws -> UInt16 { try integer() }
        func decode(_ type: UInt32.Type) throws -> UInt32 { try integer() }
        func decode(_ type: UInt64.Type) throws -> UInt64 { try integer() }

        func decode<T: Decodable>(_ type: T.Type) throws -> T {
            try T(from: JSONTreeDecoder(value, codingPath: codingPath))
        }

        /// A finite value that does not round a non-zero number to zero: `1e400` and `1e-400` are not representable,
        /// as with `JSONDecoder`.
        private func floatingPoint<T: BinaryFloatingPoint>(_ make: (String) -> T?) throws -> T {
            guard case .number(let number) = value else { throw JSONTreeDecoder.mismatch(T.self, found: value, path: codingPath) }
            guard let result = make(number.lexeme), result.isFinite, result != 0 || !Self.isNonZero(number) else {
                throw notRepresentable(number, as: T.self)
            }
            return result
        }

        /// True when a digit of the number's significand is not 0.
        private static func isNonZero(_ number: JSONNumber) -> Bool {
            number.lexeme.prefix { $0 != "e" && $0 != "E" }.contains { $0 >= "1" && $0 <= "9" }
        }

        /// The integer the number's value is: its text when it is a plain integer, else its exact whole value.
        private func integer<T: FixedWidthInteger>() throws -> T {
            guard case .number(let number) = value else { throw JSONTreeDecoder.mismatch(T.self, found: value, path: codingPath) }
            if let result = T(number.lexeme) { return result }
            // As `JSONDecoder`: `1e-400` rounds to 0 and decodes 0 here, unlike for a floating-point type.
            guard let double = Double(number.lexeme), double.isFinite, double.rounded() == double, let result = T(exactly: double)
            else { throw notRepresentable(number, as: T.self) }
            return result
        }

        private func notRepresentable(_ number: JSONNumber, as type: Any.Type) -> DecodingError {
            .dataCorrupted(.init(codingPath: codingPath, debugDescription: "Number \(number.lexeme) is not representable as \(type)."))
        }
    }

    private struct Keyed<Key: CodingKey>: KeyedDecodingContainerProtocol {
        let members: [String: JSONValue]
        let codingPath: [any CodingKey]

        var allKeys: [Key] { members.keys.compactMap { Key(stringValue: $0) } }

        func contains(_ key: Key) -> Bool { members[key.stringValue] != nil }

        func decodeNil(forKey key: Key) throws -> Bool { try member(key) == .null }

        func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try single(key).decode(type) }
        func decode(_ type: String.Type, forKey key: Key) throws -> String { try single(key).decode(type) }
        func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try single(key).decode(type) }
        func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try single(key).decode(type) }
        func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try single(key).decode(type) }
        func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try single(key).decode(type) }
        func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try single(key).decode(type) }
        func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try single(key).decode(type) }
        func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try single(key).decode(type) }
        func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try single(key).decode(type) }
        func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try single(key).decode(type) }
        func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try single(key).decode(type) }
        func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try single(key).decode(type) }
        func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try single(key).decode(type) }

        func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
            try T(from: JSONTreeDecoder(member(key), codingPath: codingPath + [key]))
        }

        func nestedContainer<NestedKey: CodingKey>(
            keyedBy type: NestedKey.Type, forKey key: Key
        ) throws -> KeyedDecodingContainer<NestedKey> {
            try JSONTreeDecoder(member(key), codingPath: codingPath + [key]).container(keyedBy: type)
        }

        func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
            try JSONTreeDecoder(member(key), codingPath: codingPath + [key]).unkeyedContainer()
        }

        func superDecoder() throws -> any Decoder {
            JSONTreeDecoder(members["super"] ?? .null, codingPath: codingPath)
        }

        func superDecoder(forKey key: Key) throws -> any Decoder {
            JSONTreeDecoder(members[key.stringValue] ?? .null, codingPath: codingPath + [key])
        }

        private func member(_ key: Key) throws -> JSONValue {
            guard let value = members[key.stringValue] else {
                let context = DecodingError.Context(codingPath: codingPath, debugDescription: "No value for \(key.stringValue).")
                throw DecodingError.keyNotFound(key, context)
            }
            return value
        }

        private func single(_ key: Key) throws -> Single {
            Single(value: try member(key), codingPath: codingPath + [key])
        }
    }

    private struct Unkeyed: UnkeyedDecodingContainer {
        let items: [JSONValue]
        let codingPath: [any CodingKey]
        private(set) var currentIndex = 0

        init(items: [JSONValue], codingPath: [any CodingKey]) {
            self.items = items
            self.codingPath = codingPath
        }

        var count: Int? { items.count }
        var isAtEnd: Bool { currentIndex >= items.count }

        mutating func decodeNil() throws -> Bool {
            guard try current() == .null else { return false }
            currentIndex += 1
            return true
        }

        mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
            let result = try T(from: elementDecoder())
            currentIndex += 1
            return result
        }

        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
            let container = try elementDecoder().container(keyedBy: type)
            currentIndex += 1
            return container
        }

        mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
            let container = try elementDecoder().unkeyedContainer()
            currentIndex += 1
            return container
        }

        mutating func superDecoder() throws -> any Decoder {
            let decoder = try elementDecoder()
            currentIndex += 1
            return decoder
        }

        private var elementPath: [any CodingKey] { codingPath + [IndexKey(currentIndex)] }

        private func current() throws -> JSONValue {
            guard !isAtEnd else {
                let context = DecodingError.Context(codingPath: elementPath, debugDescription: "Unkeyed container is at end.")
                throw DecodingError.valueNotFound(JSONValue.self, context)
            }
            return items[currentIndex]
        }

        private func elementDecoder() throws -> JSONTreeDecoder {
            JSONTreeDecoder(try current(), codingPath: elementPath)
        }
    }
}

/// The coding key of an array element, `[index]` in a coding path.
struct IndexKey: CodingKey {
    let intValue: Int?
    var stringValue: String { "Index \(intValue ?? 0)" }

    init(_ index: Int) { intValue = index }
    init?(stringValue: String) { nil }
    init?(intValue: Int) { self.intValue = intValue }
}
