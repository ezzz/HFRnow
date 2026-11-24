import SwiftUI
@testable import SwiftHFR
import Testing
import UIKit

/// Reads the size SwiftUI laid a hosted view out at.
@MainActor
private final class SizeBox { var size: CGSize = .zero }

/// #1155: the « page x / y » pill has a hit region of at least 44 x 44 pt (HIG, Buttons), measured on the real pill hosted in a
/// window: its laid-out frame is the region (`contentShape(.capsule)`), in both the glass strip and the bottom bar.
/// The same technique as `ComposerTouchTargetTests` (#1156); the two can share one helper once that PR lands.
@MainActor
@Suite(.serialized)
struct PagerPillTouchTargetTests {
    private static let minimum: CGFloat = 44

    /// The laid-out size of `content` once hosted, at its ideal size.
    private func measure<Content: View>(_ content: Content, dynamicType: DynamicTypeSize = .large) async throws -> CGSize {
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let box = SizeBox()
        let view = content
            .fixedSize()
            .onGeometryChange(for: CGSize.self, of: \.size) { box.size = $0 }
            .environment(\.dynamicTypeSize, dynamicType)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: view)
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<60 where box.size == .zero {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
        }
        return box.size
    }

    @Test(arguments: [DynamicTypeSize.xSmall, .large, .accessibility3], [true, false])
    func thePagePillHasA44PointHitRegion(size: DynamicTypeSize, drawsGlass: Bool) async throws {
        let pill = PagerPageMenuPill(current: 2, total: 9, onJump: { _ in }, drawsGlass: drawsGlass)
        let measured = try await measure(pill, dynamicType: size)
        #expect(measured.width >= Self.minimum && measured.height >= Self.minimum, "measured \(measured)")
    }

    @Test func theLoadingPillKeepsA44PointHitRegion() async throws {
        let pill = PagerPageMenuPill(current: 2, total: 9, isLoading: true, onJump: { _ in })
        let measured = try await measure(pill)
        #expect(measured.width >= Self.minimum && measured.height >= Self.minimum, "measured \(measured)")
    }
}
