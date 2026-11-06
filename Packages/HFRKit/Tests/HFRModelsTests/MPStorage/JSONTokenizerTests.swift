import Foundation
import Testing
@testable import HFRModels

/// LOT-073: the tokenizer that replaced the private-use boxing of numbers. Numbers keep their text; the grammar is what
/// Foundation's `JSONDecoder` reads (checked against it case by case, so a document it read still reads).
@Suite("MPStorage JSON tokenizer")
struct JSONTokenizerTests {
    /// What Foundation's `JSONDecoder` makes of `text`, read as any JSON value: the reference for the grammar.
    private static func foundationAccepts(_ text: String) -> Bool {
        (try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))) != nil
    }

    @Test("Numbers keep their exact text", arguments: [
        "9007199254740993", "1e17", "-0.0", "1.50", "1E+5", "-1e-7", "0.0e0", "0", "-0", "123456789012345678901234567890"
    ])
    func lexemes(lexeme: String) throws {
        #expect(try JSONTokenizer.parse("[\(lexeme)]") == .array([.number(try #require(JSONNumber(lexeme: lexeme)))]))
    }

    @Test(
        "The grammar is JSONDecoder's: RFC 8259, a byte order mark and trailing commas accepted",
        arguments: [
            // Accepted
            "{\"a\":1}", " [1] ", "\u{FEFF}[1]", "[1,]", "{\"a\":1,}", "[[],{}]", "[\"\\u00E9\\/\\b\\f\\n\\r\\t\\\"\\\\\"]",
            "[\"\\ud83d\\ude00\"]", "[true,false,null]", "\"text\"", "1",
            // Refused
            "[1,,2]", "[,1]", "{,}", "[01]", "[1.]", "[.5]", "[+1]", "[-]", "[1e]", "[0x10]", "[NaN]", "[Infinity]", "{a:1}",
            "{'a':1}", "[1]//", "[1] x", "[tru]", "[nul]", "[1 2]", "{\"a\" 1}", "[\"a\tb\"]", "[\"\\x\"]", "[\"\\u12\"]",
            "[\"\\u+123\"]", "[\u{A0}1]", "", "[", "[\"abc"
        ]
    )
    func grammar(text: String) {
        let accepted = (try? JSONTokenizer.parse(text)) != nil
        #expect(accepted == Self.foundationAccepts(text), "\(text.debugDescription)")
    }

    @Test("A repeated key keeps its first value, as JSONDecoder does")
    func repeatedKey() throws {
        let text = "{\"a\":1,\"b\":2,\"a\":3}"
        #expect(try JSONTokenizer.parse(text) == .object(["a": .number(1), "b": .number(2)]))
        #expect(try JSONDecoder().decode([String: Int].self, from: Data(text.utf8)) == ["a": 1, "b": 2])
    }

    @Test("Escapes decode to their characters; a surrogate pair to one scalar")
    func escapes() throws {
        let value = try JSONTokenizer.parse(#"["\u00e9\u00C9\u0000\/","\ud83d\ude00"]"#)
        #expect(value == .array([.string("éÉ\u{0}/"), .string("😀")]))
    }

    @Test(
        "An unpaired surrogate escape throws at its byte offset, in a value or a key",
        arguments: [
            (#"["ab\ud800"]"#, 4), (#"["\udc00"]"#, 2), (#"{"\ud800x":1}"#, 2), (#"["\ud800\u0041"]"#, 2), (#"["\ud83d\ud83d"]"#, 2)
        ]
    )
    func unpairedSurrogate(text: String, offset: Int) {
        #expect(throws: MPStorageError.unpairedSurrogate(byteOffset: offset)) { try JSONTokenizer.parse(text) }
    }

    // JSONDecoder's own limit (512 read, 513 refused) was probed on the main thread: decoding a `JSONValue` that deep
    // with it overflows a test thread's stack, which the tokenizer does not.
    @Test("Nesting: 512 levels read, 513 refused, a very deep text throws instead of overflowing")
    func depth() {
        for (levels, readable) in [(512, true), (513, false), (100_000, false)] {
            let text = String(repeating: "[", count: levels) + String(repeating: "]", count: levels)
            #expect(((try? JSONTokenizer.parse(text)) != nil) == readable, "\(levels) levels")
        }
    }

    @Test("Malformed text is a DecodingError, as it was through JSONDecoder")
    func malformed() {
        #expect(throws: DecodingError.self) { try JSONTokenizer.parse("{\"data\":[}") }
        #expect(throws: DecodingError.self) { try MPStorageCodec.decode("{\"data\":[1.]}") }
    }
}
