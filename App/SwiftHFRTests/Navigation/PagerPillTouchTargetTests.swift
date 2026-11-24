import SwiftUI
@testable import SwiftHFR
import Testing
import UIKit

/// Reads the size SwiftUI laid a hosted view out at.
@MainActor
private final class SizeBox { var size: CGSize = .zero }

/// #1155: the « page x / y » pill has a hit region of at least 44 x 44 pt (HIG, Buttons), measured on the real pill hosted in a
/// window (its laid-out frame is the region, `contentShape(.rect)`), while the visible capsule keeps hugging its text.
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

    @Test(arguments: [DynamicTypeSize.xSmall, .large], [true, false])
    func thePagePillHasA44PointHitRegion(size: DynamicTypeSize, drawsGlass: Bool) async throws {
        let pill = PagerPageMenuPill(current: 2, total: 9, onJump: { _ in }, drawsGlass: drawsGlass)
        let measured = try await measure(pill, dynamicType: size)
        #expect(measured.width >= Self.minimum && measured.height >= Self.minimum, "measured \(measured)")
    }

    /// Guard: at an accessibility size the text already makes the pill taller than 44 pt.
    @Test func thePagePillStaysAtLeast44PointsAtAnAccessibilitySize() async throws {
        let pill = PagerPageMenuPill(current: 2, total: 9, onJump: { _ in })
        let measured = try await measure(pill, dynamicType: .accessibility3)
        #expect(measured.width >= Self.minimum && measured.height >= Self.minimum, "measured \(measured)")
    }

    @Test func theLoadingPillKeepsA44PointHitRegion() async throws {
        let pill = PagerPageMenuPill(current: 2, total: 9, isLoading: true, onJump: { _ in })
        let measured = try await measure(pill)
        #expect(measured.width >= Self.minimum && measured.height >= Self.minimum, "measured \(measured)")
    }

    /// The label's own capsule hugs its text (text plus 12 / 6 pt padding), shorter than the hit frame the pill puts around it.
    @Test(arguments: [DynamicTypeSize.xSmall, .large])
    func theVisibleCapsuleStillHugsItsText(size: DynamicTypeSize) async throws {
        let menu = PagerPageMenu(current: 2, total: 9)
        let text = try await measure(Text(menu.label).monospacedDigit(), dynamicType: size)
        let label = try await measure(PagerPillLabel(menu: menu), dynamicType: size)
        #expect(abs(label.height - (text.height + 12)) < 0.5 && abs(label.width - (text.width + 24)) < 0.5, "label \(label), text \(text)")
        #expect(label.height < Self.minimum, "the capsule must not grow to the hit frame: \(label)")
    }

    /// The bar's item group draws the glass behind the pill (a second capsule would nest); the strip has none, so the pill draws it.
    /// Both placements of `PagerToolbar` read this function.
    @Test func thePillDrawsItsOwnGlassOnlyInTheStrip() {
        #expect(PagerToolbar.pillDrawsGlass(in: .bottomBar) == false)
        #expect(PagerToolbar.pillDrawsGlass(in: .inset) == true)
    }

    /// Operator 2026-11-24: the strip's arrows are as tall as its pill, 44 pt, hit region and glass capsule alike (the glass
    /// button style wraps the laid-out frame).
    @Test(arguments: [DynamicTypeSize.xSmall, .large])
    func theStripArrowsAre44PointsInTheGlassStyle(size: DynamicTypeSize) async throws {
        let step = PagerToolbar.Step(enabled: true, action: {})
        let pager = PagerToolbar(first: step, previous: step, next: step, last: step, status: .pageOf(2, 9), jump: { _ in })
        let arrow = pager.stripArrow("Page suivante", "chevron.right", pager.next).labelStyle(.iconOnly).buttonStyle(.glass)
        let measured = try await measure(arrow, dynamicType: size)
        // Exactly the pill's 44 pt (a little slack for rounding), not more: a taller arrow would no longer match the pill.
        #expect((Self.minimum...(Self.minimum + 1)).contains(measured.width), "measured \(measured)")
        #expect((Self.minimum...(Self.minimum + 1)).contains(measured.height), "measured \(measured)")
    }
}
