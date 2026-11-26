import HFRModels
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// #1121: a destructive `Button` in a themed list row takes the accessible error colour; Legacy is untouched.
@MainActor
@Suite(.serialized)
struct ThemedDestructiveTests {
    /// A dark inset-grouped list with one destructive row button (a tall swatch as its label), `modified` or not, disabled or not.
    private struct Root: View {
        let model: ThemeSettingsModel
        let modified: Bool
        let isDisabled: Bool
        var body: some View {
            List {
                Group {
                    if modified {
                        Button(role: .destructive) {} label: { Rectangle().frame(height: 200) }
                            .themedDestructive().disabled(isDisabled)
                    } else {
                        Button(role: .destructive) {} label: { Rectangle().frame(height: 200) }.disabled(isDisabled)
                    }
                }.themedListRow()
            }
            .listStyle(.insetGrouped)
            .appTheme(model)
        }
    }

    private func model(themed: Bool) throws -> ThemeSettingsModel {
        let catalog = try ThemeFixtures.catalog()
        let model = ThemeSettingsModel(store: InMemorySettingsStore(), catalog: catalog)
        if themed { model.select(try #require(catalog.themes.first { $0.id == "test-theme" })) }
        model.mode = .dark
        return model
    }

    private func show(_ root: Root) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 300, height: 700)
        window.rootViewController = UIHostingController(rootView: root)
        window.isHidden = false
        return window
    }

    /// The RGB at the middle of the first row, 150 pt from the left and 150 from the top.
    private func label(of window: UIWindow) -> [Int] {
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        if let cgImage = image.cgImage {
            let scale = image.scale, size = window.bounds.size
            context?.draw(cgImage, in: CGRect(x: -150 * scale, y: -(size.height - 150) * scale,
                                              width: size.width * scale, height: size.height * scale))
        }
        return data.prefix(3).map(Int.init)
    }

    /// Waits for the window to settle on a pixel `condition` accepts, then returns that pixel.
    private func settled(_ window: UIWindow, until condition: ([Int]) -> Bool) async -> [Int] {
        for _ in 0..<500 {
            if condition(label(of: window)) { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return label(of: window)
    }

    private func near(_ lhs: [Int], _ rhs: [Int]) -> Bool { zip(lhs, rhs).allSatisfy { abs($0 - $1) <= 2 } }

    /// Under a theme the label is `errorText` (#FF827A in dark), not the role's system red: the explicit style wins in a row.
    @Test func underAThemeTheLabelIsTheAccessibleRed() async throws {
        let window = try show(Root(model: try model(themed: true), modified: true, isDisabled: false))
        defer { window.isHidden = true }
        let pixel = await settled(window) { near($0, [0xFF, 0x82, 0x7A]) }
        #expect(near(pixel, [0xFF, 0x82, 0x7A]), "\(pixel)")
    }

    /// Disabled, the themed label is dimmer than enabled (not left at full strength by the explicit style) and still not the
    /// row's own surface (#1A2430): dimmed, not dropped.
    @Test func underAThemeADisabledLabelIsDimmed() async throws {
        let window = try show(Root(model: try model(themed: true), modified: true, isDisabled: true))
        defer { window.isHidden = true }
        let pixel = await settled(window) { $0.reduce(0, +) < 0xFF + 0x82 + 0x7A - 60 }
        #expect(pixel.reduce(0, +) < 0xFF + 0x82 + 0x7A - 60, "\(pixel)")
        #expect(!near(pixel, [0x1A, 0x24, 0x30]), "\(pixel)")
    }

    /// Legacy: the modifier changes no pixel, enabled or disabled.
    @Test func underLegacyTheModifierChangesNoPixel() async throws {
        for isDisabled in [false, true] {
            let plain = try show(Root(model: try model(themed: false), modified: false, isDisabled: isDisabled))
            defer { plain.isHidden = true }
            let modified = try show(Root(model: try model(themed: false), modified: true, isDisabled: isDisabled))
            defer { modified.isHidden = true }
            let reference = await settled(plain) { $0 != [0, 0, 0] }
            let pixel = await settled(modified) { $0 == reference }
            #expect(pixel == reference, "disabled \(isDisabled): \(reference) vs \(pixel)")
        }
    }
}
