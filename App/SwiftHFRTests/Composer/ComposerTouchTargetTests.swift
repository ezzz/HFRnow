import SwiftUI
@testable import SwiftHFR
import Testing
import UIKit

/// Reads the size SwiftUI laid a hosted view out at.
@MainActor
private final class SizeBox { var size: CGSize = .zero }

/// #1156: every composer button has a hit region of at least 44 x 44 pt (HIG, Buttons), measured on the real buttons hosted in a
/// window (their laid-out frame is the region, `contentShape(.rect)`), whatever the look of the control.
@MainActor
@Suite(.serialized)
struct ComposerTouchTargetTests {
    private static let minimum = ComposerHeader.hitSize

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

    @Test(arguments: [DynamicTypeSize.xSmall, .large, .accessibility3])
    func theImageChipCrossHasA44PointHitRegion(size: DynamicTypeSize) async throws {
        let measured = try await measure(ComposerImageChipCross(isEnabled: true) {}, dynamicType: size)
        #expect(measured.width >= Self.minimum && measured.height >= Self.minimum, "measured \(measured)")
    }

    @Test func thePollAnswerRemoveButtonHasA44PointHitRegion() async throws {
        let measured = try await measure(PollAnswerRemoveButton(number: 3) {})
        #expect(measured.width >= Self.minimum && measured.height >= Self.minimum, "measured \(measured)")
    }

    /// Legacy's bar (no card) clamps the cell too: compact density and the 70 % text size gave 40 and 28 pt. The formatting
    /// toolbar and the control row both read this clamp.
    @Test(arguments: [(ListDensity.compact, 100), (.regular, 70), (.compact, 70), (.regular, 100)])
    func theControlRowCellIsAtLeast44PointsInBothChromes(density: ListDensity, percent: Int) {
        let metrics = ComposerBarMetrics(density: density, scale: TextScale(percent: percent))
        for inCard in [true, false] {
            let cell = ComposerControlRow.cellSize(metrics.cellSize, inCard: inCard)
            #expect(cell >= Self.minimum, "\(density) \(percent) % inCard \(inCard): \(cell)")
        }
    }
}
