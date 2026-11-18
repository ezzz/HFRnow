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

    /// The header and the control row read the same value up to the bar's cap on the text size's growth (Dynamic Type times the
    /// text scale); past it the header's buttons keep the cap's size, never larger than the card tools'.
    @Test(arguments: metricsCases, [ComposerToolStyle.plain, .pills])
    func theHeaderAndTheControlRowShareOneSize(metrics: ComposerBarMetrics, style: ComposerToolStyle) {
        let shared = ComposerToolSize(metrics: metrics, style: style)
        let header = ComposerHeader.buttonSize(metrics: metrics, inCard: true, style: style)
        #expect(ComposerControlRow.toolSize(metrics: metrics, inCard: true, style: style) == shared)
        if metrics.dynamicType * metrics.scale.factor <= ComposerHeader.maxScaleFactor + 0.001 {
            #expect(header == shared)
        } else {
            #expect(header.diameter < shared.diameter && header.glyph < shared.glyph, "capped: \(header) against \(shared)")
        }
    }

    /// Three buttons, their hit areas (44 pt at least) and the bar's insets and gaps fit the narrowest supported width (320 pt) at
    /// every text size, in the floating row and in legacy's bar, with and without the drafts button.
    @Test(arguments: metricsCases, [ComposerToolStyle.plain, .pills])
    func theCappedButtonsFitTheNarrowestWidth(metrics: ComposerBarMetrics, style: ComposerToolStyle) {
        for inCard in [true, false] {
            let size = ComposerHeader.buttonSize(metrics: metrics, inCard: inCard, style: style)
            for floats in [true, false] {
                let reserved = ComposerHeader.reservedWidth(floats: floats, buttons: 3)
                let used = 3 * max(size.diameter, ComposerHeader.hitSize) + reserved
                #expect(used <= 320, "inCard \(inCard), floats \(floats): \(used) pt for \(size)")
            }
        }
    }

    /// The cap holds the product of Dynamic Type and the text scale, whichever of the two is large.
    @Test func theCapBoundsTheProductOfDynamicTypeAndTheTextScale() {
        let metrics = ComposerBarMetrics(density: .regular, scale: TextScale(percent: 130), dynamicType: 3.1)
        let capped = metrics.capped(at: ComposerHeader.maxScaleFactor)
        #expect(abs(capped.dynamicType * capped.scale.factor - ComposerHeader.maxScaleFactor) < 0.001)
        let small = ComposerBarMetrics(density: .regular, scale: TextScale(percent: 100), dynamicType: 1.2)
        #expect(small.capped(at: ComposerHeader.maxScaleFactor) == small, "under the cap nothing changes")
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
