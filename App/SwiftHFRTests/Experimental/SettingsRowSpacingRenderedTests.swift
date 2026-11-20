import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// The rendered gap between a switch's title and the description under it (#1128). The reference is the « MP multiples → dark
/// topic » row as dev-swift drew it before #1128 (`ReferenceDescribedRow`); every row that shows a description must sit at that
/// visible distance. Measured on the pixels of a hosted window, not on the constants.
@MainActor
@Suite(.serialized)
struct SettingsRowSpacingRenderedTests {
    /// dev-swift's `DescribedFeatureRow` (#1014), frozen: the title's switch, then the description 2 pt under it.
    private struct ReferenceDescribedRow: View {
        let title: String
        let explanation: String
        @State private var isOn = false

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Toggle(title, isOn: $isOn)
                Text(explanation).scaledFont(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Hosts `row` alone in a light Form and returns the points between the bottom of the first line of text and the top of the
    /// next one, read on the text columns only (the switch sits further right).
    private func gap(of row: some View) async throws -> CGFloat {
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = .light
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 300)
        let form = Form { row.listRowBackground(Color.white) }.scrollContentBackground(.hidden).background(Color.white)
        window.rootViewController = UIHostingController(rootView: form)
        window.isHidden = false
        defer { window.isHidden = true }
        try? await Task.sleep(for: .milliseconds(600))
        window.layoutIfNeeded()
        let scale: CGFloat = 3
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        return try Self.gap(in: try #require(image.cgImage), scale: scale)
    }

    /// The bands of ink (a pixel row with a non-white pixel in the text columns) and the blank run between the first two.
    private static func gap(in image: CGImage, scale: CGFloat) throws -> CGFloat {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let columns = Int(36 * scale)..<Int(220 * scale)
        let inked = (0..<height).map { y in
            columns.contains { x in
                let offset = (y * width + x) * 4
                return Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2]) < 3 * 215
            }
        }
        var bands: [(top: Int, bottom: Int)] = []
        for (y, isInked) in inked.enumerated() where isInked {
            if let last = bands.last, last.bottom == y - 1 { bands[bands.count - 1].bottom = y } else { bands.append((y, y)) }
        }
        try #require(bands.count >= 2, "found \(bands.count) band(s) of text")
        return CGFloat(bands[1].top - bands[0].bottom - 1) / scale
    }

    private static func settings() -> ExperimentalSettings { ExperimentalSettings(store: InMemorySettingsStore()) }

    /// The reference row with the same texts as the row under test, so the glyphs (descenders, ascenders) cancel out.
    private func referenceGap(_ title: String, _ explanation: String) async throws -> CGFloat {
        try await gap(of: ReferenceDescribedRow(title: title, explanation: explanation))
    }

    @Test func anOptionWithItsExplanationShownSitsAtTheReferenceGap() async throws {
        for feature in ExperimentalFeature.allCases {
            let reference = try await referenceGap(feature.title, feature.explanation)
            let shown = try await gap(of: ExperimentalFeatureRow(feature: feature, settings: Self.settings(), isExplained: true))
            #expect(abs(shown - reference) <= 1, "\(feature): \(shown) pt, reference \(reference) pt")
        }
    }

    @Test func theMPStorageRowSitsAtTheReferenceGap() async throws {
        let fixture = try await MPStorageSyncModelTests.make(thread: nil, state: .on)
        let reference = try await referenceGap("Activer le stockage MP", MPStorageSettingsRows.stateText(fixture.model.record?.state))
        let shown = try await gap(of: MPStorageSettingsRows(model: fixture.model))
        #expect(abs(shown - reference) <= 1, "MP storage: \(shown) pt, reference \(reference) pt")
    }
}
