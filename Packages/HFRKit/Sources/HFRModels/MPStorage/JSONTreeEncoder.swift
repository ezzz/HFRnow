/// Encodes `Encodable` values into a `JSONValue` tree for `JSONWriter`, as `JSONEncoder` does into text: integers in
/// decimal, a non-finite floating-point value refused, a value that encodes nothing written as `{}`.
///
/// A `JSONValue` is stored whole (its `encode(to:)` calls `store(_:)`), so the unmodelled parts keep their numbers' text.
final class JSONTreeEncoder: Encoder {
    let codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }
    /// What was encoded; nil until a container or a value is written.
    private(set) var node: JSONTreeNode?

    init(codingPath: [any CodingKey] = []) {
        self.codingPath = codingPath
    }

    /// The tree `value` encodes to.
    /// - Throws: `EncodingError.invalidValue` for a value that encodes nothing, a non-finite floating-point value or a
    ///   number that is not valid JSON (`JSONNumber(Double.infinity)`).
    static func encode(_ value: some Encodable) throws -> JSONValue {
        let encoder = JSONTreeEncoder()
        try value.encode(to: encoder)
        guard let node = encoder.node else {
            throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "The value did not encode anything."))
        }
        return node.value
    }

    /// Stores `value` as this encoder's result, after checking that every number in it is valid JSON.
    func store(_ value: JSONValue) throws {
        try Self.validate(value, path: codingPath)
        node = JSONTreeNode(.value(value))
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        KeyedEncodingContainer(Keyed(node: claim(.object([:])), codingPath: codingPath))
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        Unkeyed(node: claim(.array([])), codingPath: codingPath)
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        Single(encoder: self)
    }

    /// The node of this encoder: an existing object or array is reused, as `JSONEncoder` does for repeated requests.
    /// A request for another kind replaces the node where `JSONEncoder` traps: only a malformed `encode(to:)` does it,
    /// and the codec then writes its last container instead of crashing the app.
    private func claim(_ content: JSONTreeNode.Content) -> JSONTreeNode {
        if let node, node.content.isSameKind(as: content) { return node }
        let created = JSONTreeNode(content)
        node = created
        return created
    }

    private static func validate(_ value: JSONValue, path: [any CodingKey]) throws {
        switch value {
        case .number(let number) where !JSONNumber.isValid(number.lexeme):
            throw EncodingError.invalidValue(number.lexeme, .init(codingPath: path, debugDescription: "Not a JSON number"))
        case .array(let items):
            for item in items { try validate(item, path: path) }
        case .object(let members):
            for member in members.values { try validate(member, path: path) }
        default:
            break
        }
    }

    /// A floating-point value written as Swift's shortest form, whole values without `.0` (`JSONNumber(Double)`); a
    /// non-finite value is refused, as `JSONEncoder` does by default.
    private static func number<T: BinaryFloatingPoint & LosslessStringConvertible>(
        _ value: T, path: [any CodingKey]
    ) throws -> JSONValue {
        var text = value.description
        if text.hasSuffix(".0") { text.removeLast(2) }
        guard value.isFinite, let number = JSONNumber(lexeme: text) else {
            let context = EncodingError.Context(codingPath: path, debugDescription: "Unable to encode \(value) directly in JSON.")
            throw EncodingError.invalidValue(value, context)
        }
        return .number(number)
    }

    private static func number(_ value: some FixedWidthInteger) -> JSONValue {
        // A decimal integer is always a valid lexeme.
        .number(JSONNumber(lexeme: String(value)) ?? 0)
    }

    // MARK: - Containers

    private struct Single: SingleValueEncodingContainer {
        let encoder: JSONTreeEncoder
        var codingPath: [any CodingKey] { encoder.codingPath }

        func encodeNil() throws { try encoder.store(.null) }
        func encode(_ value: Bool) throws { try encoder.store(.bool(value)) }
        func encode(_ value: String) throws { try encoder.store(.string(value)) }
        func encode(_ value: Double) throws { try encoder.store(JSONTreeEncoder.number(value, path: codingPath)) }
        func encode(_ value: Float) throws { try encoder.store(JSONTreeEncoder.number(value, path: codingPath)) }
        func encode(_ value: Int) throws { try encoder.store(JSONTreeEncoder.number(value)) }
        func encode(_ value: Int8) throws { try encoder.store(JSONTreeEncoder.number(value)) }
        func encode(_ value: Int16) throws { try encoder.store(JSONTreeEncoder.number(value)) }
        func encode(_ value: Int32) throws { try encoder.store(JSONTreeEncoder.number(value)) }
        func encode(_ value: Int64) throws { try encoder.store(JSONTreeEncoder.number(value)) }
        func encode(_ value: UInt) throws { try encoder.store(JSONTreeEncoder.number(value)) }
        func encode(_ value: UInt8) throws { try encoder.store(JSONTreeEncoder.number(value)) }
        func encode(_ value: UInt16) throws { try encoder.store(JSONTreeEncoder.number(value)) }
        func encode(_ value: UInt32) throws { try encoder.store(JSONTreeEncoder.number(value)) }
        func encode(_ value: UInt64) throws { try encoder.store(JSONTreeEncoder.number(value)) }
        func encode<T: Encodable>(_ value: T) throws { try value.encode(to: encoder) }
    }

    private struct Keyed<Key: CodingKey>: KeyedEncodingContainerProtocol {
        let node: JSONTreeNode
        let codingPath: [any CodingKey]

        mutating func encodeNil(forKey key: Key) throws { node.set(key.stringValue, JSONTreeNode(.value(.null))) }

        mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
            let child = JSONTreeEncoder(codingPath: codingPath + [key])
            try value.encode(to: child)
            node.set(key.stringValue, child.node ?? JSONTreeNode(.value(.object([:]))))
        }

        mutating func nestedContainer<NestedKey: CodingKey>(
            keyedBy keyType: NestedKey.Type, forKey key: Key
        ) -> KeyedEncodingContainer<NestedKey> {
            let child = JSONTreeNode(.object([:]))
            node.set(key.stringValue, child)
            return KeyedEncodingContainer(Keyed<NestedKey>(node: child, codingPath: codingPath + [key]))
        }

        mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
            let child = JSONTreeNode(.array([]))
            node.set(key.stringValue, child)
            return Unkeyed(node: child, codingPath: codingPath + [key])
        }

        mutating func superEncoder() -> any Encoder { superEncoder(named: "super", path: codingPath) }

        mutating func superEncoder(forKey key: Key) -> any Encoder {
            superEncoder(named: key.stringValue, path: codingPath + [key])
        }

        private func superEncoder(named name: String, path: [any CodingKey]) -> any Encoder {
            let child = JSONTreeEncoder(codingPath: path)
            node.set(name, JSONTreeNode(.deferred(child)))
            return child
        }
    }

    private struct Unkeyed: UnkeyedEncodingContainer {
        let node: JSONTreeNode
        let codingPath: [any CodingKey]
        var count: Int { node.count }

        mutating func encodeNil() throws { node.append(JSONTreeNode(.value(.null))) }

        mutating func encode<T: Encodable>(_ value: T) throws {
            let child = JSONTreeEncoder(codingPath: codingPath + [IndexKey(count)])
            try value.encode(to: child)
            node.append(child.node ?? JSONTreeNode(.value(.object([:]))))
        }

        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
            let child = JSONTreeNode(.object([:]))
            let path = codingPath + [IndexKey(count)]
            node.append(child)
            return KeyedEncodingContainer(Keyed<NestedKey>(node: child, codingPath: path))
        }

        mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
            let child = JSONTreeNode(.array([]))
            let path = codingPath + [IndexKey(count)]
            node.append(child)
            return Unkeyed(node: child, codingPath: path)
        }

        mutating func superEncoder() -> any Encoder {
            let child = JSONTreeEncoder(codingPath: codingPath + [IndexKey(count)])
            node.append(JSONTreeNode(.deferred(child)))
            return child
        }
    }
}
