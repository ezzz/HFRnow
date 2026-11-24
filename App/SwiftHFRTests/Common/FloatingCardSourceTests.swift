import Foundation
import Testing

/// #693: the floating card is defined once. A card copied back into a screen (a material or glass at the card's 12-pt radius, or the
/// literal `RoundedRectangle(cornerRadius: 12)` the issue greps for) drifts from the others the next time one of them changes.
struct FloatingCardSourceTests {
    private static let appSources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "SwiftHFR")

    private static let sharedFile = "Common/FloatingCard.swift"

    /// Every Swift file of the app target: its path relative to `App/SwiftHFR`, and its text.
    private static func sources() throws -> [(file: String, text: String)] {
        let root = appSources.standardizedFileURL.path
        let enumerator = try #require(FileManager.default.enumerator(at: appSources, includingPropertiesForKeys: nil))
        var result: [(file: String, text: String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let file = String(url.standardizedFileURL.path.dropFirst(root.count + 1))
            result.append((file, try String(contentsOf: url, encoding: .utf8)))
        }
        return result
    }

    /// The 1-based lines of `text` that copy the card: the literal shape, or a material or glass at the 12-pt radius on the same
    /// line or the line before it (a modifier split after `in:`). `120` and `12.5` are other radii.
    static func cardCopies(in text: String) -> [Int] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return lines.indices.compactMap { index in
            let line = lines[index]
            if line.contains(/RoundedRectangle\(cornerRadius: 12(?![0-9.])/) { return index + 1 }
            guard line.contains(/cornerRadius: 12(?![0-9.])/) else { return nil }
            let context = (index > 0 ? lines[index - 1] : "") + line
            return context.contains("Material") || context.contains("glassEffect") ? index + 1 : nil
        }
    }

    @Test func theAppSourcesAreFound() throws {
        // Guards the test below against passing on an empty walk.
        let shared = try #require(try Self.sources().first { $0.file == Self.sharedFile })
        #expect(Self.cardCopies(in: shared.text) != [])
    }

    @Test func noScreenCopiesTheCard() throws {
        let copies = try Self.sources().filter { $0.file != Self.sharedFile }.flatMap { source in
            Self.cardCopies(in: source.text).map { "\(source.file):\($0)" }
        }
        #expect(copies == [])
    }

    @Test(arguments: [
        ".background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))",
        ".glassEffect(.regular, in: .rect(cornerRadius: 12))",
        ".background(.thinMaterial, in: .rect(cornerRadius: 12, style: .continuous))",
        ".background(\n    .regularMaterial, in: .rect(cornerRadius: 12)\n)",
        ".glassEffect(.regular, in:\n    .rect(cornerRadius: 12))",
        ".clipShape(RoundedRectangle(cornerRadius: 12))",
    ])
    func aCopyIsCaught(_ source: String) {
        #expect(Self.cardCopies(in: source) != [])
    }

    @Test(arguments: [
        ".background(.regularMaterial, in: .rect(cornerRadius: 120))",
        ".glassEffect(.regular, in: .rect(cornerRadius: 12.5))",
        ".background(.regularMaterial, in: RoundedRectangle(cornerRadius: 120))",
        ".clipShape(.rect(cornerRadius: 12))",
        ".background(.regularMaterial, in: .capsule)\n.clipShape(.rect(cornerRadius: 10))",
    ])
    func anotherShapeIsNot(_ source: String) {
        #expect(Self.cardCopies(in: source) == [])
    }
}
