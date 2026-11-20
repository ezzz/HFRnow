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
    @Test(arguments: metricsCases)
    func theHeaderAndTheControlRowShareOneSize(metrics: ComposerBarMetrics) {
        let shared = ComposerToolSize(metrics: metrics)
        let header = ComposerHeader.buttonSize(metrics: metrics, inCard: true)
        #expect(ComposerControlRow.toolSize(metrics: metrics, inCard: true) == shared)
        if metrics.dynamicType * metrics.scale.factor <= ComposerHeader.maxScaleFactor + 0.001 {
            #expect(header == shared)
        } else {
            #expect(header.diameter < shared.diameter && header.glyph < shared.glyph, "capped: \(header) against \(shared)")
        }
    }

    /// Three buttons, their hit areas (44 pt at least) and the bar's insets and gaps fit the narrowest supported width (320 pt) at
    /// every text size, in the floating row and in legacy's bar, with and without the drafts button.
    @Test(arguments: metricsCases)
    func theCappedButtonsFitTheNarrowestWidth(metrics: ComposerBarMetrics) {
        for inCard in [true, false] {
            let size = ComposerHeader.buttonSize(metrics: metrics, inCard: inCard)
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

    /// In the card the chip is the circle's diameter; outside it the whole cell; the glyph is the bar's, medium weight.
    @Test(arguments: metricsCases)
    func theCircleIsTheChipInTheCardAndTheCellOutsideIt(metrics: ComposerBarMetrics) {
        let inCard = ComposerToolSize(metrics: metrics, inCard: true)
        let outside = ComposerToolSize(metrics: metrics, inCard: false)
        #expect(inCard.cell >= ComposerHeader.hitSize)
        #expect(inCard.diameter == ComposerChip.chipDiameter(cell: inCard.cell))
        #expect(outside.diameter == outside.cell)
        #expect(inCard.glyph == metrics.glyphSize)
        #expect(ComposerToolSize.glyphWeight == .medium)
    }
}
