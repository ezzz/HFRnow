import SwiftUI
import Testing

@testable import SwiftHFR

/// #1126: the composer's close, drafts and send buttons and the card's tools are one size, read from `ComposerToolSize`.
@MainActor
struct ComposerToolSizeTests {
    nonisolated private static let metricsCases: [ComposerBarMetrics] = [ListDensity.regular, .compact].flatMap { density in
        [(100, CGFloat(1)), (130, 1), (100, 1.6), (130, 3.1)].map { percent, dynamicType in
            ComposerBarMetrics(density: density, scale: TextScale(percent: percent), dynamicType: dynamicType)
        }
    }

    /// The header and the control row read the same value, whatever the density, text scale and Dynamic Type.
    @Test(arguments: metricsCases, [ComposerToolStyle.plain, .pills])
    func theHeaderAndTheControlRowShareOneSize(metrics: ComposerBarMetrics, style: ComposerToolStyle) {
        let shared = ComposerToolSize(metrics: metrics, style: style)
        #expect(ComposerHeader.buttonSize(metrics: metrics, inCard: true, style: style) == shared)
        #expect(ComposerControlRow.toolSize(metrics: metrics, inCard: true, style: style) == shared)
    }

    /// Three buttons, their hit areas (44 pt at least) and the bar's insets fit the width at every text size (#1126, delta review).
    @Test(arguments: metricsCases, [CGFloat(320), 375, 402, 440])
    func theButtonsFitTheBarsWidth(metrics: ComposerBarMetrics, width: CGFloat) {
        let size = ComposerToolSize(metrics: metrics, style: .pills)
        for floats in [true, false] {
            for buttons in [2, 3] {
                let reserved = ComposerHeader.reservedWidth(floats: floats, buttons: buttons)
                let fitted = size.fitting(width: width, buttons: buttons, reserved: reserved)
                let used = CGFloat(buttons) * max(fitted.diameter, ComposerHeader.hitSize) + reserved
                #expect(used <= width + 0.5, "\(buttons) buttons, floats \(floats), width \(width): \(used)")
                #expect(fitted.diameter <= size.diameter && fitted.glyph <= size.glyph)
            }
        }
        #expect(size.fitting(width: 0, buttons: 3, reserved: 16) == size, "unmeasured: the size is kept")
    }

    /// The chip (pills) or the cell (plain) is the circle's diameter; the glyph is the bar's, medium weight.
    @Test(arguments: metricsCases)
    func theSizeFollowsTheToolStyle(metrics: ComposerBarMetrics) {
        let pills = ComposerToolSize(metrics: metrics, style: .pills)
        let plain = ComposerToolSize(metrics: metrics, style: .plain)
        #expect(pills.cell == plain.cell)
        #expect(pills.cell >= ComposerHeader.hitSize)
        #expect(pills.diameter == ComposerToolStyle.chipDiameter(cell: pills.cell))
        #expect(plain.diameter == plain.cell)
        #expect(pills.glyph == metrics.glyphSize)
        #expect(ComposerToolSize.glyphWeight == .medium)
    }
}
