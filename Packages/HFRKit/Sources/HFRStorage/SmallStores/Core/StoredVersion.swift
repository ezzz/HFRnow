import Foundation

/// The `version` of a stored JSON document, read before the rest (#1184): a newer format may not decode as this one, and
/// must still be reported as newer ("update the app"), not as damaged.
enum StoredVersion {
    /// The version field of `data`; throws when there is none.
    static func read(_ data: Data) throws -> Int {
        try JSONDecoder().decode(Probe.self, from: data).version
    }

    private struct Probe: Decodable {
        let version: Int
    }
}
