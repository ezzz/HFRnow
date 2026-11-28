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

    /// A section of three rows and a one-row section (« Thème »), the way Réglages builds them, or the same rows with no position.
    private struct Grouped: View {
        let appearance: ThemeAppearance
        var look = ListLook.classic
        var sectioned = true
        var body: some View {
            List {
                if sectioned {
                    ThemedSection("A") { ForEach(0..<3, id: \.self) { _ in Text("").frame(height: 80) } }
                    ThemedSection("B") { Text("").frame(height: 80) }
                } else {
                    Section("A") { ForEach(0..<4, id: \.self) { _ in Text("").frame(height: 80).themedListRow() } }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.listLook, look)
            .environment(\.themeAppearance, appearance)
        }
    }

    private struct Corner {
        let name: String
        let x: CGFloat
        let y: CGFloat
    }

    /// A rendered window: pixel reads in points.
    private struct Frame {
        let width: Int, height: Int, scale: CGFloat
        let data: [UInt8]

        func isOutline(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < width, y < height else { return false }
            let offset = (y * width + x) * 4
            return zip([Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2])], [0x17, 0x75, 0x17])
                .allSatisfy { abs($0 - $1) <= 3 }
        }

        /// The outline in the box of `radius` points around the point (`x`, `y`): the corner arc is there.
        func hasOutline(near x: CGFloat, _ y: CGFloat, radius: CGFloat = 2) -> Bool {
            let (cx, cy, reach) = (Int(x * scale), Int(y * scale), Int(radius * scale))
            return (cy - reach...cy + reach).contains { row in (cx - reach...cx + reach).contains { isOutline($0, row) } }
        }

        /// The runs of outline pixels down the line `x` points from the left: their first y in points.
        func runs(atX x: CGFloat) -> [CGFloat] {
            var starts: [CGFloat] = []
            var inside = false
            for row in 0..<height {
                let hit = isOutline(Int(x * scale), row)
                if hit && !inside { starts.append(CGFloat(row) / scale) }
                inside = hit
            }
            return starts
        }

        /// The first and last outline pixel along the line `y` points from the top, in points.
        func sides(atY y: CGFloat) -> (CGFloat, CGFloat)? {
            let hits = (0..<width).filter { isOutline($0, Int(y * scale)) }
            guard let first = hits.first, let last = hits.last else { return nil }
            return (CGFloat(first) / scale, CGFloat(last + 1) / scale)
        }
    }

    private func render(_ root: Grouped) async throws -> Frame {
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 300, height: 700)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(rootView: root)
        window.isHidden = false
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(800))
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let cgImage = try #require(image.cgImage)
        var data = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        let context = CGContext(
            data: &data, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return Frame(width: cgImage.width, height: cgImage.height, scale: image.scale, data: data)
    }

    /// Rétro-like: one outline per section: a line along the top and one along the bottom of each section and none between its
    /// rows, the sides joined to them by the rounded corners, the one-row section bounded on its four corners.
    @Test func aFlatThemeOutlinesEachSectionAsOne() async throws {
        let frame = try await render(Grouped(appearance: try flat(outlined: true)))
        let runs = frame.runs(atX: 150)
        #expect(runs.count == 4, "horizontal outline lines at y = \(runs)")
        guard runs.count == 4, let (left, right) = frame.sides(atY: runs[0] + 40) else { return }
        // The 45 degree point of each rounded corner (radius 26, the line 0.5 pt in): 26 (1 - cos 45) = 7.6 pt.
        let inset: CGFloat = 0.5 + 26 * (1 - 0.7071)
        var corners: [Corner] = []
        for (section, top, bottom) in [("A", runs[0], runs[1]), ("B", runs[2], runs[3])] {
            for (side, x) in [("left", left + inset), ("right", right - inset)] {
                corners.append(Corner(name: "\(section) top \(side)", x: x, y: top + inset))
                corners.append(Corner(name: "\(section) bottom \(side)", x: x, y: bottom - inset))
            }
        }
        for corner in corners { #expect(frame.hasOutline(near: corner.x, corner.y), "\(corner.name) corner is open") }
    }

    /// A theme whose card stands out (here #3A4A60 on #101820) draws none, token or not.
    @Test func aThemeWhoseCardStandsOutDrawsNoOutline() async throws {
        let raised = try appearance {
            $0["surface"] = "#3A4A60"
            $0["groupOutline"] = "#177517"
        }
        #expect(try await render(Grouped(appearance: raised)).runs(atX: 150).isEmpty)
    }

    /// Legacy, the dense look and rows outside a `ThemedSection` (the iPad sidebar has no card) draw none, even under a flat theme.
    @Test func legacyTheDenseLookAndRowsWithNoPositionDrawNoOutline() async throws {
        #expect(try await render(Grouped(appearance: .standard)).runs(atX: 150).isEmpty)
        #expect(try await render(Grouped(appearance: try flat(outlined: true), look: .dense)).runs(atX: 150).isEmpty)
        let bare = try await render(Grouped(appearance: try flat(outlined: true), sectioned: false))
        #expect(bare.runs(atX: 150).isEmpty && bare.sides(atY: 100) == nil)
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
