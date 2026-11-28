import HFRModels
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// LOT-193 (#734): the OG themes' `listStyle: ogTable` draws the web forum's table in the native lists: section headers as a
/// header band, rows alternating `surface` and `alternateCell`. Every other theme keeps its rows (and Legacy has none).
@MainActor
@Suite(.serialized)
struct ThemedTableListTests {
    private func model(_ id: String) throws -> ThemeSettingsModel {
        let catalog = ThemeCatalog.bundled
        let model = ThemeSettingsModel(store: InMemorySettingsStore(), catalog: catalog)
        model.select(try #require(catalog.themes.first { $0.id == id }))
        return model
    }

    private func rgb(_ color: UIColor) -> [Int] {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue].map { Int(($0 * 255).rounded()) }
    }

    private func hex(_ value: Int) -> [Int] { [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF] }

    private func near(_ lhs: [Int], _ rhs: [Int]) -> Bool { zip(lhs, rhs).allSatisfy { abs($0 - $1) <= 2 } }

    // MARK: The colour rule

    @Test func onlyAnOGThemeGivesTheListTableColours() throws {
        let gris = try #require(try model("og-gris").appearance.listColors)
        let table = try #require(gris.table)
        #expect(rgb(table.headerBand) == hex(0x202530) && rgb(table.onHeaderBand) == hex(0x8E8E8E))
        #expect(rgb(table.alternateCell) == hex(0xE8E8E8) && rgb(gris.row) == hex(0xDCDCDC))
        #expect(try model("swift").appearance.listColors?.table == nil)
        #expect(ThemeAppearance.standard.listColors == nil)
    }

    /// The row background: the alternate cell only in the table look, on an unselected classic row; a selected row keeps `selection`.
    @Test func anAlternateRowIsTheAlternateCellOnlyInTheTableLook() throws {
        let gris = try #require(try model("og-gris").appearance.listColors)
        let swift = try #require(try model("swift").appearance.listColors)
        #expect(rgb(ThemedListRow.background(gris, isSelected: false, isAlternate: true, look: .classic)
            .uiColor) == hex(0xE8E8E8))
        #expect(rgb(ThemedListRow.background(gris, isSelected: false, isAlternate: false, look: .classic).uiColor) == hex(0xDCDCDC))
        #expect(rgb(ThemedListRow.background(gris, isSelected: true, isAlternate: true, look: .classic).uiColor) == rgb(gris.selectedRow))
        #expect(ThemedListRow.background(swift, isSelected: false, isAlternate: true, look: .classic)
            == ThemedListRow.background(swift, isSelected: false, isAlternate: false, look: .classic))
    }

    // MARK: In a real list

    private struct TableList: View {
        let model: ThemeSettingsModel
        var body: some View {
            List {
                Section {
                    ForEach(0..<4, id: \.self) { index in
                        Text("").frame(height: 100).themedListRow(isAlternate: index.isMultiple(of: 2) == false)
                    }
                } header: { Text("Section").themedSectionHeader() }
            }
            .listStyle(.insetGrouped)
            .appTheme(model)
        }
    }

    /// Every colour of the window along the vertical line at `x`, one render.
    private func column(of window: UIWindow, x: Int) -> [[Int]] {
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let cgImage = image.cgImage else { return [] }
        let width = cgImage.width, height = cgImage.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let column = min(width - 1, Int(CGFloat(x) * image.scale))
        return (0..<height).map { row in (0..<3).map { Int(data[(row * width + column) * 4 + $0]) } }
    }

    private func show(_ root: some View) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 300, height: 700)
        window.rootViewController = UIHostingController(rootView: root)
        window.isHidden = false
        return window
    }

    private func seen(_ colors: [UInt32], in window: UIWindow) async throws -> Bool {
        let wanted = colors.map { hex(Int($0)) }
        for _ in 0..<250 {
            let line = column(of: window, x: 150)
            if wanted.allSatisfy({ color in line.contains { near($0, color) } }) { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    /// OG gris: the header band (#202530) and both row colours (#DCDCDC, #E8E8E8) show in the one list; the control theme
    /// shows its own rows only (no band), so the test fails without the change.
    @Test func theTableListShowsTheBandAndAlternatingCells() async throws {
        let window = try show(TableList(model: try model("og-gris")))
        defer { window.isHidden = true }
        #expect(try await seen([0x202530, 0xDCDCDC, 0xE8E8E8], in: window))
    }

    @Test func aStandardThemeKeepsOneRowColourAndNoBand() async throws {
        let window = try show(TableList(model: try model("swift")))
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(600))
        let line = column(of: window, x: 150)
        #expect(!line.contains { near($0, hex(0x202530)) })
        #expect(!line.contains { near($0, hex(0xE8E8E8)) })
    }
}

private extension Color {
    /// The colour as UIKit's, for the tests' comparisons.
    var uiColor: UIColor { UIColor(self) }
}
