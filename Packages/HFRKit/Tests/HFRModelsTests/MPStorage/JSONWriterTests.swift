import Foundation
import Testing
@testable import HFRModels

/// LOT-073: the writer and the tree coder that replaced `JSONEncoder` plus marker unboxing. On values whose numbers are
/// integers, the output is byte for byte `JSONEncoder`'s with the codec's options (key order, escapes), so documents are
/// written exactly as before; numbers otherwise keep their text.
@Suite("MPStorage JSON writer")
struct JSONWriterTests {
    private static func foundation(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try #require(String(validating: try encoder.encode(value), as: UTF8.self))
    }

    /// Every character below U+0020, then the characters `JSONEncoder` leaves as they are.
    private static let awkward: String = {
        var text = ""
        for value in 0..<0x20 { text.unicodeScalars.append(Unicode.Scalar(UInt8(value))) }
        return text + "\u{7F}\"\\/\u{2028}\u{2029}é\u{FEFF}"
    }()

    @Test("Strings: every escape as JSONEncoder writes it")
    func escapes() throws {
        let value = JSONValue.array([.string(Self.awkward), .string(""), .string("plain")])
        #expect(JSONWriter.write(value) == (try Self.foundation(value)))
    }

    @Test("Keys sort by their UTF-8 bytes, as JSONEncoder sorts them")
    func keyOrder() throws {
        let keys = [
            "b", "B", "a10", "a9", "a", "é", "z", "Z", "_x", "a-b", "a_b", "10", "9", "ａ", "aa", "A", "A\u{30A}b", "\u{FFFF}", ""
        ]
        var members: [String: JSONValue] = [:]
        for (index, key) in keys.enumerated() { members[key] = .number(JSONNumber(Int64(index))) }
        let value = JSONValue.object(members)
        #expect(JSONWriter.write(value) == (try Self.foundation(value)))
    }

    @Test("A nested document with every kind of value, integers only, is JSONEncoder's text")
    func nested() throws {
        let value = JSONValue.object([
            "data": .array([.object(["version": .string("0.1"), "list": .array([]), "n": .number(-12), "flag": .bool(true)])]),
            "extra": .object(["null": .null, "deep": .array([.array([.object([:])])]), Self.awkward: .string(Self.awkward)])
        ])
        #expect(JSONWriter.write(value) == (try Self.foundation(value)))
    }

    @Test("Numbers are written with their exact text; JSONEncoder would rewrite them")
    func numbers() throws {
        let lexemes = ["9007199254740993", "1e17", "-0.0", "1.50", "1E+5"]
        let value = JSONValue.array(try lexemes.map { .number(try #require(JSONNumber(lexeme: $0))) })
        #expect(JSONWriter.write(value) == "[" + lexemes.joined(separator: ",") + "]")
        #expect(try Self.foundation(value) != JSONWriter.write(value))
    }

    @Test("A text read and written back is the same text, whitespace aside")
    func roundTrip() throws {
        let text = #"{"a":[1.50,-0.0,1e17,"\u0001\n",{"x":null,"y":true}],"b":"é/","c":9007199254740993}"#
        #expect(JSONWriter.write(try JSONTokenizer.parse(text)) == text)
    }

    @Test("A nested value that encodes nothing is written {}, as JSONEncoder writes it, in an object and in an array")
    func nestedNothing() throws {
        struct Silent: Encodable { func encode(to encoder: any Encoder) throws {} }
        struct Holder: Encodable {
            let inner = Silent()
            let list = [Silent()]
        }
        let text = JSONWriter.write(try JSONTreeEncoder.encode(Holder()))
        #expect(text == #"{"inner":{},"list":[{}]}"#)
        #expect(text == (try Self.foundation(Holder())))
    }

    @Test(
        "A super encoder keeps what the super writes, a value, an array or an object, as JSONEncoder does",
        arguments: SuperShape.allCases
    )
    func superEncoders(shape: SuperShape) throws {
        let value = Derived(shape: shape)
        let text = JSONWriter.write(try JSONTreeEncoder.encode(value))
        #expect(text == (try Self.foundation(value)))
    }

    @Test("The tree coder refuses what JSONEncoder refuses: a non-finite double, a value that encodes nothing")
    func refusals() {
        #expect(throws: EncodingError.self) { try JSONTreeEncoder.encode(Double.infinity) }
        #expect(throws: EncodingError.self) { try JSONTreeEncoder.encode(JSONValue.number(JSONNumber(Double.nan))) }
        struct Nothing: Encodable { func encode(to encoder: any Encoder) throws {} }
        #expect(throws: EncodingError.self) { try JSONTreeEncoder.encode(Nothing()) }
    }
}

/// What `Base` writes in the super encoders `Derived` asks for.
enum SuperShape: CaseIterable, Sendable {
    case single, unkeyed, keyed
}

private struct Base: Encodable {
    let shape: SuperShape

    func encode(to encoder: any Encoder) throws {
        switch shape {
        case .single:
            var container = encoder.singleValueContainer()
            try container.encode(1)
        case .unkeyed:
            var container = encoder.unkeyedContainer()
            try container.encode(1)
            try container.encode(2)
        case .keyed:
            var container = encoder.container(keyedBy: DynamicKey.self)
            try container.encode(1, forKey: DynamicKey("base"))
        }
    }
}

/// Encodes `Base` through every super encoder: the keyed default (`super`), a keyed one for a key, and an unkeyed one.
private struct Derived: Encodable {
    let shape: SuperShape

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        try container.encode(2, forKey: DynamicKey("x"))
        try Base(shape: shape).encode(to: container.superEncoder())
        try Base(shape: shape).encode(to: container.superEncoder(forKey: DynamicKey("parent")))
        var list = container.nestedUnkeyedContainer(forKey: DynamicKey("list"))
        try list.encode(3)
        try Base(shape: shape).encode(to: list.superEncoder())
    }
}
