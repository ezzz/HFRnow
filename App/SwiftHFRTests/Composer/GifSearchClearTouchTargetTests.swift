import SwiftUI
@testable import SwiftHFR
import Testing
import UIKit

/// What a hosted view measured: its laid-out frame, and the size its hit region reported (when it has a probe).
@MainActor
private final class Measured {
    var layout: CGRect = .zero
    var region: CGSize = .zero
    var window: UIWindow?
    var host: UIViewController?
}

/// #1296: the GIF picker's clear-search ✕ has a hit region of at least 44 x 44 pt (HIG, Buttons) and its glyph stays where it
/// was. Same measurement as `ComposerTouchTargetTests`; a tap itself needs an XCUITest (#893).
@MainActor
@Suite(.serialized)
struct GifSearchClearTouchTargetTests {
    private static let minimum = ComposerHeader.hitSize

    private func host<Content: View>(
        _ content: (Measured) -> Content, dynamicType: DynamicTypeSize, probed: Bool = true
    ) async throws -> Measured {
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let measured = Measured()
        let view = content(measured)
            .fixedSize()
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { measured.layout = $0 })
            .appTypography(TextScale(percent: 100), density: .regular)
            // Outside `appTypography`, whose `ScaledFont` reads the size from the environment it is given (#1298).
            .environment(\.dynamicTypeSize, dynamicType)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller
        window.isHidden = false
        measured.window = window
        measured.host = controller
        for _ in 0..<60 where measured.layout == .zero || (probed && measured.region == .zero) {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
        }
        return measured
    }

    @Test(arguments: [DynamicTypeSize.xSmall, .large, .accessibility5])
    func theClearCrossHasA44PointHitRegion(size: DynamicTypeSize) async throws {
        let button = try await host({ probe in GifSearchClearButton(action: {}, regionProbe: { probe.region = $0 }) },
                                    dynamicType: size)
        #expect(button.region.width >= Self.minimum && button.region.height >= Self.minimum, "region \(button.region)")
    }

    /// The look stays: the button lays out (size and position) exactly as the bare glyph did, so the search bar does not move.
    @Test(arguments: [DynamicTypeSize.xSmall, .large, .accessibility5])
    func theClearCrossKeepsTheLayoutOfItsGlyph(size: DynamicTypeSize) async throws {
        let glyph = try await host({ _ in Image(systemName: "xmark.circle.fill") }, dynamicType: size, probed: false).layout
        let button = try await host({ probe in GifSearchClearButton(action: {}, regionProbe: { probe.region = $0 }) },
                                    dynamicType: size).layout
        #expect(abs(button.width - glyph.width) < 0.5 && abs(button.height - glyph.height) < 0.5,
                "layout \(button.size) against the glyph's \(glyph.size)")
        #expect(abs(button.minX - glyph.minX) < 0.5 && abs(button.minY - glyph.minY) < 0.5,
                "origin \(button.origin) against the glyph's \(glyph.origin)")
    }
}
