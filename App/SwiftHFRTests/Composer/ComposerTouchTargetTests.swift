import SwiftUI
@testable import SwiftHFR
import Testing
import UIKit

/// The laid-out frame of a hosted view and the window it sits in.
@MainActor
private final class Hosted {
    var frame: CGRect = .zero
    var window: UIWindow?
    var host: UIViewController?
}

/// #1156: every composer button has a hit region of at least 44 x 44 pt (HIG, Buttons), measured on the real buttons hosted in a
/// window, by their laid-out frame, which `minimumHitRegion()` makes the region.
///
/// Not covered: that `contentShape(.rect)` lets the transparent margin of a `.plain` button take taps, and the poll row's
/// negative padding. A hit test cannot show it in a unit-test host: the hosting view answers every point of the window with
/// itself, with or without the shape (probed, #1156), and a tap needs an XCUITest on a device or simulator (#893).
@MainActor
@Suite(.serialized)
struct ComposerTouchTargetTests {
    private static let minimum = ComposerHeader.hitSize

    private func host<Content: View>(
        _ content: Content, dynamicType: DynamicTypeSize = .large, percent: Int = 100
    ) async throws -> Hosted {
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let hosted = Hosted()
        let view = content
            .fixedSize()
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { hosted.frame = $0 }
            .environment(\.dynamicTypeSize, dynamicType)
            .appTypography(TextScale(percent: percent), density: .regular)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller
        window.isHidden = false
        hosted.window = window
        hosted.host = controller
        for _ in 0..<60 where hosted.frame == .zero {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
        }
        return hosted
    }

    @Test(arguments: [DynamicTypeSize.xSmall, .large, .accessibility5])
    func theImageChipCrossHasA44PointHitRegion(size: DynamicTypeSize) async throws {
        let hosted = try await host(ComposerImageChipCross(isEnabled: true) {}, dynamicType: size)
        #expect(hosted.frame.width >= Self.minimum && hosted.frame.height >= Self.minimum, "measured \(hosted.frame.size)")
    }

    /// The glyph stops growing at accessibility sizes, so it never hides its 56 pt thumbnail.
    @Test func theChipCrossGlyphIsCappedAtAccessibilitySizes() async throws {
        let hosted = try await host(ComposerImageChipCross(isEnabled: true) {}, dynamicType: .accessibility5)
        #expect(hosted.frame.width <= 44 && hosted.frame.height <= 44, "measured \(hosted.frame.size)")
    }

    /// The ⊖ takes its own glyph's room in the row (the text field keeps its width) at every text size, and its region (the
    /// glyph plus the overhang each side) is 44 pt at least.
    @Test(arguments: [(DynamicTypeSize.large, 100), (.accessibility5, 100), (.xSmall, 100), (.large, 70), (.xxxLarge, 100)])
    func thePollAnswerRemoveButtonKeepsItsLayoutAndHasA44PointRegion(size: DynamicTypeSize, percent: Int) async throws {
        let glyph = try await host(Image(systemName: "minus.circle.fill"), dynamicType: size, percent: percent).frame
        let hosted = try await host(PollAnswerRemoveButton(number: 3) {}, dynamicType: size, percent: percent)
        #expect(abs(hosted.frame.width - glyph.width) < 0.5 && abs(hosted.frame.height - glyph.height) < 0.5,
                "layout \(hosted.frame.size) against the glyph's \(glyph.size)")
        #expect(glyph.width + 2 * PollAnswerRemoveButton.overhang(of: glyph.width) >= Self.minimum)
        #expect(glyph.height + 2 * PollAnswerRemoveButton.overhang(of: glyph.height) >= Self.minimum)
    }

    /// The control row's and the formatting toolbar's cells: legacy's bar clamps the hit region too (compact density and the
    /// 70 % text size gave 40 and 28 pt).
    @Test(arguments: [(ListDensity.compact, 100), (.regular, 70), (.compact, 70), (.regular, 100)])
    func theControlRowCellIsAtLeast44PointsInBothChromes(density: ListDensity, percent: Int) {
        let metrics = ComposerBarMetrics(density: density, scale: TextScale(percent: percent))
        for inCard in [true, false] {
            let cell = ComposerControlRow.hitCell(ComposerControlRow.cellSize(metrics.cellSize, inCard: inCard))
            #expect(cell >= Self.minimum, "\(density) \(percent) % inCard \(inCard): \(cell)")
        }
    }

    /// The look stays: outside the card the header's circles (close, drafts, send) are still drawn at legacy's cell.
    @Test(arguments: [(ListDensity.compact, 100), (.regular, 70), (.compact, 70)])
    func theHeaderCirclesOutsideTheCardKeepLegacysSize(density: ListDensity, percent: Int) {
        let metrics = ComposerBarMetrics(density: density, scale: TextScale(percent: percent))
        let size = ComposerToolSize(metrics: metrics, inCard: false)
        #expect(size.diameter == metrics.cellSize)
        #expect(size.cell == metrics.cellSize)
    }
}
