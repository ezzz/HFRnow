import Foundation
import Testing

/// #693: the floating card is defined once. A card copied back into a screen (a material or glass at the card's 12-pt radius, or the
/// literal `RoundedRectangle(cornerRadius: 12)` the issue greps for) drifts from the others the next time one of them changes.
struct FloatingCardSourceTests {
    private static let appSources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "SwiftHFR")

    /// One line of an app source file.
    private struct SourceLine {
        /// Relative to `App/SwiftHFR`.
        let file: String
        let number: Int
        let text: String
    }

    /// Every Swift line of the app target.
    private static func lines() throws -> [SourceLine] {
        let root = appSources.standardizedFileURL.path
        let enumerator = try #require(FileManager.default.enumerator(at: appSources, includingPropertiesForKeys: nil))
        var result: [SourceLine] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let file = String(url.standardizedFileURL.path.dropFirst(root.count + 1))
            let text = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                result.append(SourceLine(file: file, number: index + 1, text: String(line)))
            }
        }
        return result
    }

    private static let sharedFile = "Common/FloatingCard.swift"

    @Test func theAppSourcesAreFound() throws {
        // Guards the two tests below against passing on an empty walk.
        #expect(try Self.lines().contains { $0.file == Self.sharedFile && $0.text.contains("RoundedRectangle(cornerRadius: 12)") })
    }

    @Test func onlyTheSharedCardSpellsTheCardShape() throws {
        let copies = try Self.lines().filter { $0.file != Self.sharedFile && $0.text.contains("RoundedRectangle(cornerRadius: 12)") }
        #expect(copies.map { "\($0.file):\($0.number)" } == [])
    }

    @Test func noScreenPutsAMaterialOrGlassOnTheCardShape() throws {
        let copies = try Self.lines().filter { line in
            line.file != Self.sharedFile && line.text.contains("cornerRadius: 12")
                && (line.text.contains("Material") || line.text.contains("glassEffect"))
        }
        #expect(copies.map { "\($0.file):\($0.number)" } == [])
    }
}
