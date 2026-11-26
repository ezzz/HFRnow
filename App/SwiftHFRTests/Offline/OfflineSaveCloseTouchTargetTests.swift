import SwiftUI
@testable import SwiftHFR
import Testing
import UIKit

/// What a hosted view measured: its laid-out frame, and the frames its probes reported (global coordinates).
@MainActor
private final class Measured {
    var layout: CGRect = .zero
    var region: CGRect = .zero
    var glyph: CGRect = .zero
    var field: CGRect = .zero
    var window: UIWindow?
    var host: UIViewController?
}

/// #1329: the offline-save banner's ✕ has a hit region of at least 44 x 44 pt (HIG, Buttons), its glyph stays where it
/// was, and the region does not reach into the banner's text. Same measurement as `GifSearchClearTouchTargetTests`; a tap itself needs an
/// XCUITest (#893).
@MainActor
@Suite(.serialized)
struct OfflineSaveCloseTouchTargetTests {
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

    private func button(_ measured: Measured) -> OfflineSaveCloseButton {
        OfflineSaveCloseButton(action: {}, regionProbe: { measured.region = $0 }, glyphProbe: { measured.glyph = $0 })
    }

    @Test(arguments: [DynamicTypeSize.xSmall, .large, .accessibility5])
    func theCloseCrossHasA44PointHitRegion(size: DynamicTypeSize) async throws {
        let hosted = try await host({ button($0) }, dynamicType: size)
        #expect(hosted.region.width >= Self.minimum && hosted.region.height >= Self.minimum, "region \(hosted.region.size)")
    }

    /// The look stays: the button lays out with the bare glyph's size and origin, and the visible glyph sits at the centre of it.
    @Test(arguments: [DynamicTypeSize.xSmall, .large, .accessibility5])
    func theCloseCrossKeepsTheLayoutAndThePlaceOfItsGlyph(size: DynamicTypeSize) async throws {
        let glyph = try await host(
            { _ in Label("Fermer", systemImage: "xmark").labelStyle(.iconOnly) }, dynamicType: size, probed: false
        ).layout
        let hosted = try await host({ button($0) }, dynamicType: size)
        let layout = hosted.layout
        #expect(abs(layout.width - glyph.width) < 0.5 && abs(layout.height - glyph.height) < 0.5,
                "layout \(layout.size) against the glyph's \(glyph.size)")
        #expect(abs(hosted.glyph.midX - layout.midX) < 0.5 && abs(hosted.glyph.midY - layout.midY) < 0.5,
                "glyph centre \(hosted.glyph.midX), \(hosted.glyph.midY) against the layout's \(layout.midX), \(layout.midY)")
    }

    /// In the banner's stack the region never reaches into the text: a tap on the message must not close the banner.
    @Test(arguments: [DynamicTypeSize.xSmall, .large, .accessibility5])
    func theCloseCrossRegionDoesNotReachIntoTheText(size: DynamicTypeSize) async throws {
        let hosted = try await host({ measured in
            HStack(spacing: OfflineSaveCloseButton.spacing) {
                Text("1 page enregistrée hors ligne")
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { measured.field = $0 })
                button(measured)
            }
        }, dynamicType: size)
        #expect(hosted.field != .zero)
        #expect(hosted.region.minX >= hosted.field.maxX - 0.01, "region \(hosted.region) over the text \(hosted.field)")
        #expect(hosted.region.width >= Self.minimum, "region \(hosted.region.size)")
    }
}
