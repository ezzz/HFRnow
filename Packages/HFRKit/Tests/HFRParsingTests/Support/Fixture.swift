import Foundation

/// Loads files of the shared capture corpus (`Fixtures/captures`, LOT-001) and per-lot synthetic pages.
enum Fixture {
    /// A fixture that could not be found or decoded.
    struct Missing: Error, CustomStringConvertible {
        let path: String
        var description: String { "Missing fixture \(path)" }
    }

    /// Text of a captured page, e.g. `capture("R32a-topic-poll-anon")`.
    static func capture(_ name: String, extension fileExtension: String = "html") throws -> String {
        try text(name, extension: fileExtension, subdirectory: "Fixtures/captures")
    }

    /// Text of a file under `Fixtures/<subdirectory>`.
    static func text(_ name: String, extension fileExtension: String, subdirectory: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: subdirectory) else {
            throw Missing(path: "\(subdirectory)/\(name).\(fileExtension)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
