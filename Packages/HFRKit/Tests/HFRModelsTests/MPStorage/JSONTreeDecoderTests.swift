import Foundation
import Testing
@testable import HFRModels

/// LOT-073: the tree decoder converts as `JSONDecoder` does (checked against it), so the modelled fields read the same
/// documents: a number reads as an integer when its value is one, never a string as a number or the reverse.
@Suite("MPStorage JSON tree decoder")
struct JSONTreeDecoderTests {
    private struct Box<Value: Decodable & Equatable>: Decodable, Equatable {
        let value: Value
    }

    /// Both decoders give the same value, or both refuse.
    private static func agree<Value: Decodable & Equatable>(_ type: Value.Type, _ json: String) -> Bool {
        let text = "{\"value\":\(json)}"
        let foundation = try? JSONDecoder().decode(Box<Value>.self, from: Data(text.utf8))
        let tree = try? Box<Value>(from: JSONTreeDecoder(JSONTokenizer.parse(text)))
        return foundation == tree
    }

    private static let samples = [
        "1", "1.0", "1e2", "1.5", "-0", "-1", "300", "70000", "1e400", "9007199254740993", "1E-2", "\"1\"", "true", "null",
        "[1]", "{}", "\"text\""
    ]

    @Test("Integers, floating point, strings and booleans convert as with JSONDecoder", arguments: samples)
    func conversions(json: String) {
        #expect(Self.agree(Int.self, json), "Int \(json)")
        #expect(Self.agree(Int8.self, json), "Int8 \(json)")
        #expect(Self.agree(UInt.self, json), "UInt \(json)")
        #expect(Self.agree(Int64.self, json), "Int64 \(json)")
        #expect(Self.agree(Double.self, json), "Double \(json)")
        #expect(Self.agree(Float.self, json), "Float \(json)")
        #expect(Self.agree(String.self, json), "String \(json)")
        #expect(Self.agree(Bool.self, json), "Bool \(json)")
        #expect(Self.agree(Int?.self, json), "Int? \(json)")
        #expect(Self.agree([Int].self, json), "[Int] \(json)")
    }

    @Test("A missing key and a type mismatch are the errors JSONDecoder gives")
    func errors() throws {
        let tree = JSONTreeDecoder(try JSONTokenizer.parse("{\"other\":1}"))
        #expect(throws: DecodingError.self) { try Box<Int>(from: tree) }
        let mismatch = JSONTreeDecoder(try JSONTokenizer.parse("{\"value\":\"1\"}"))
        do {
            _ = try Box<Int>(from: mismatch)
            Issue.record("expected a type mismatch")
        } catch DecodingError.typeMismatch(_, let context) {
            #expect(context.codingPath.map(\.stringValue) == ["value"])
        } catch {
            Issue.record("expected a type mismatch, got \(error)")
        }
    }
}
