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
        return try decoded(Data(contentsOf: url))
    }

    /// UTF-8, else ISO-8859-1: `R98a` (a `www.hardware.fr` page) is Latin-1, as the legacy login reader allows
    /// (`LoginService.swift:137-140`, `anonymize.py read_text`).
    static func decoded(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(String.UnicodeScalarView(data.map { Unicode.Scalar($0) }))
    }
}
