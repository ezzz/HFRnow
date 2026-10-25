import Foundation

/// Encodes then decodes a value, so tests exercise the exact persisted representation.
func roundTrip<Value: Codable>(_ value: Value) throws -> Value {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(Value.self, from: data)
}

/// Decodes UTF-8 data to a string, failing the test instead of silently repairing invalid bytes.
func text(of data: Data) throws -> String {
    guard let text = String(bytes: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
    return text
}
