import Foundation

/// Reads and writes the MPStorage JSON text, with the guards the forum needs (E24, HFR-PROTOCOL §3.3, §6).
public enum MPStorageCodec {
    /// Largest serialized document, in UTF-8 bytes, this app writes (redface2 `MAX_CONTENT_FORM_BYTES`, E24).
    /// HFR's own limit was never observed; beyond it HFR truncates silently, which would corrupt the JSON.
    public static let maximumSerializedBytes = 65_536

    /// Decodes the JSON text of the storage message. It never resets or repairs: invalid JSON or a missing
    /// `data` key throws. Removing U+00A0 that a rendered page adds is the reader's job (LOT-038).
    /// Numbers keep their exact text; a `\u` escape of a lone surrogate throws `unpairedSurrogate`.
    public static func decode(_ text: String) throws -> MPStorageDocument {
        try MPStorageDocument(from: JSONTreeDecoder(JSONTokenizer.parse(text)))
    }

    /// Serializes a document for the `content_form` field: compact, keys sorted, slashes unescaped.
    /// Throws `MPStorageError` when the document has no `0.1` entry, holds a character outside the
    /// Basic Multilingual Plane anywhere (including other clients' namespaces), or exceeds `limit` bytes.
    public static func encodeForWriting(_ document: MPStorageDocument, limit: Int = maximumSerializedBytes) throws -> String {
        guard document.writableEntryIndex != nil else { throw MPStorageError.noWritableEntry }
        let tree = try JSONTreeEncoder.encode(document)
        let text = JSONWriter.write(tree)
        if let codePoint = firstNonBMPScalar(in: text) {
            throw MPStorageError.nonBMPCharacter(path: nonBMPPath(in: tree, path: "") ?? "", codePoint: codePoint)
        }
        let byteCount = text.utf8.count
        guard byteCount <= limit else { throw MPStorageError.tooLarge(byteCount: byteCount, limit: limit) }
        return text
    }

    /// Throws `nonBMPCharacter` when any string of `value` (keys included) cannot be stored; `path` prefixes the report.
    static func validateWritable(_ value: some Encodable, path: String) throws {
        let tree = try JSONTreeEncoder.encode(value)
        guard let codePoint = firstNonBMPScalar(in: JSONWriter.write(tree)) else { return }
        throw MPStorageError.nonBMPCharacter(path: path + (nonBMPPath(in: tree, path: "") ?? ""), codePoint: codePoint)
    }

    private static func firstNonBMPScalar(in text: String) -> UInt32? {
        text.unicodeScalars.first { $0.value > 0xFFFF }?.value
    }

    private static func containsNonBMP(_ text: String) -> Bool { firstNonBMPScalar(in: text) != nil }

    /// Path of the first string (key or value) holding a non-BMP character, e.g. `.data[0].bookmarks.list[2].label`.
    private static func nonBMPPath(in value: JSONValue, path: String) -> String? {
        switch value {
        case .string(let text):
            return containsNonBMP(text) ? path : nil
        case .array(let items):
            for (index, item) in items.enumerated() {
                if let found = nonBMPPath(in: item, path: "\(path)[\(index)]") { return found }
            }
            return nil
        case .object(let members):
            for (key, member) in members.sorted(by: { $0.key < $1.key }) {
                if containsNonBMP(key) { return "\(path).<key>" }
                if let found = nonBMPPath(in: member, path: "\(path).\(key)") { return found }
            }
            return nil
        case .null, .bool, .number:
            return nil
        }
    }
}
