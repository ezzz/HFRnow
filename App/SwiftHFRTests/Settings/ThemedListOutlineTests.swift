import HFRModels
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// #1456: under a flat theme (`surface` = the page, Rétro 5250) a grouped list draws a 1 pt outline in `groupOutline` around its
/// rows; a theme whose card stands out, and Legacy, draw none.
@MainActor
@Suite(.serialized)
struct ThemedListOutlineTests {
    private static let outline = [0x17, 0x75, 0x17]

    /// The test theme with its dark variant edited by `edit`.
    private func appearance(_ edit: (inout [String: Any]) -> Void) throws -> ThemeAppearance {
        var json = try #require(try JSONSerialization.jsonObject(with: ThemeFixtures.data("test-theme")) as? [String: Any])
        var variants = try #require(json["variants"] as? [String: Any])
        var dark = try #require(variants["dark"] as? [String: Any])
        edit(&dark)
        variants["dark"] = dark
        json["variants"] = variants
        let theme = try JSONDecoder().decode(ThemeDefinition.self, from: JSONSerialization.data(withJSONObject: json))
        var result = ThemeAppearance.standard
        result.themeVariants = theme.variants
        return result
    }

    /// Rétro-like: `surface` is the page's black; `outlined` adds the Rétro outline token.
    private func flat(outlined: Bool) throws -> ThemeAppearance {
        try appearance {
            $0["background"] = "#000000"
            $0["surface"] = "#000000"
            if outlined { $0["groupOutline"] = "#177517" }
        }
    }

    private struct Grouped: View {
        let appearance: ThemeAppearance
        var look = ListLook.classic
        var body: some View {
            List { Section { ForEach(0..<4, id: \.self) { _ in Text("").frame(height: 200).themedListRow() } } }
                .listStyle(.insetGrouped)
                .environment(\.listLook, look)
                .environment(\.themeAppearance, appearance)
        }
    }

    /// The pixels of the window's line `y` pt from the top, as RGB triples.
    private func scanLine(_ window: UIWindow, y: CGFloat) -> [[Int]] {
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let cgImage = image.cgImage else { return [] }
        let width = cgImage.width, row = Int(y * image.scale)
        var data = [UInt8](repeating: 0, count: width * 4)
        let context = CGContext(
            data: &data, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(cgImage, in: CGRect(x: 0, y: -(cgImage.height - row - 1), width: width, height: cgImage.height))
        return (0..<width).map { [Int(data[$0 * 4]), Int(data[$0 * 4 + 1]), Int(data[$0 * 4 + 2])] }
    }

    /// How many pixels of the third row's middle line are the outline colour: only the sides of the rows can be.
    private func outlinePixels(_ root: Grouped) async throws -> Int {
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 300, height: 700)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(rootView: root)
        window.isHidden = false
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(800))
        return scanLine(window, y: 550).filter { zip($0, Self.outline).allSatisfy { abs($0 - $1) <= 3 } }.count
    }

    /// Rétro-like: each side of a row carries the 1 pt outline (at least 2 pixels on the line).
    @Test func aFlatThemeOutlinesItsRows() async throws {
        let count = try await outlinePixels(Grouped(appearance: try flat(outlined: true)))
        #expect(count >= 2, "outline pixels \(count)")
    }

    /// A theme whose card stands out (here #3A4A60 on #101820) draws none, token or not.
    @Test func aThemeWhoseCardStandsOutDrawsNoOutline() async throws {
        let raised = try appearance {
            $0["surface"] = "#3A4A60"
            $0["groupOutline"] = "#177517"
        }
        #expect(try await outlinePixels(Grouped(appearance: raised)) == 0)
    }

    /// Legacy and the dense look (rows with no card) draw none, even under a flat theme.
    @Test func legacyAndTheDenseLookDrawNoOutline() async throws {
        #expect(try await outlinePixels(Grouped(appearance: .standard)) == 0)
        #expect(try await outlinePixels(Grouped(appearance: try flat(outlined: true), look: .dense)) == 0)
    }

    /// The decision is the model's: flat means below 1.05:1, and the token falls back to `separator`.
    @Test func theOutlineColourFallsBackToTheSeparator() throws {
        let appearance = try flat(outlined: false)
        let dark = try #require(appearance.themeVariants?.dark)
        #expect(!dark.cardStandsOut && dark.resolvedGroupOutline == dark.separator)
        #expect(appearance.groupOutlineColor != nil)
        #expect(ThemeAppearance.standard.groupOutlineColor == nil)
    }
}
