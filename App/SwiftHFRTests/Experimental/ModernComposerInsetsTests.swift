import CoreGraphics
@testable import SwiftHFR
import SwiftUI
import Testing

/// Density, in-app text size and Dynamic Type factor (large, XL, AX3): the text size slider's ends included.
private let composerSizes: [ComposerSize] = [ListDensity.regular, .compact].flatMap { density in
    [(100, CGFloat(1)), (70, 1), (130, 1), (100, 19.0 / 17.0), (100, 28.0 / 17.0)].map {
        ComposerSize(density: density, percent: $0.0, dynamicType: $0.1)
    }
}

/// Issue #895 (operator, 2026-11-14; the Claude iOS app's composer is the reference): the modern composer's margins are one
/// shared gap, `FloatingSpacing.gap` (operator decision of 2026-11-16 on #820 and #895, about 8 pt), its buttons and tools have
/// one icon size, and every hit area stays at least 44 pt. Legacy's chrome (an iPad, or « Composer moderne » off) keeps its
/// paddings.
@MainActor
struct ModernComposerInsetsTests {
    /// The card tools' chip diameter at the default text size and density (`ComposerBarMetrics`), which the floating buttons now use.
    private static let defaultDiameter = ComposerToolSize(
        metrics: ComposerBarMetrics(density: .regular, scale: TextScale(percent: 100))
    ).diameter

    @Test func theSharedGapIsTheReferencesEightPoints() {
        #expect(FloatingSpacing.gap == 8)
    }

    @Test func theTextCardIsTheGapFromTheSidesAndFromTheKeyboard() {
        let insets = ComposerChrome.docked.cardInsets
        #expect(insets.leading == FloatingSpacing.gap)
        #expect(insets.trailing == FloatingSpacing.gap)
        #expect(insets.bottom == FloatingSpacing.gap)
        #expect(insets.top == 0, "the floating buttons' bottom inset is the gap above the card")
    }

    /// What the eye sees around a circle is the gap: its hit area's slack plus the bar's inset, on every side. Under a 28 pt
    /// circle (never at the card tools' 36 pt minimum) the slack alone is wider than the gap: the hit area stays 44 pt and the
    /// circle is the slack away, never closer than the gap.
    @Test(arguments: composerSizes)
    func eachFloatingCircleIsTheGapFromTheSidesThePageAndTheCard(size: ComposerSize) {
        let metrics = size.metrics
        let slack = ComposerHeader.hitSlack(diameter: ComposerToolSize(metrics: metrics).diameter)
        let insets = ComposerChrome.docked.headerInsets(diameter: ComposerToolSize(metrics: metrics).diameter)
        let horizontal = max(FloatingSpacing.gap, slack.width)
        let vertical = max(FloatingSpacing.gap, slack.height)
        #expect(abs(insets.leading + slack.width - horizontal) < 0.001)
        #expect(abs(insets.trailing + slack.width - horizontal) < 0.001)
        #expect(abs(insets.top + slack.height - vertical) < 0.001)
        #expect(abs(insets.bottom + slack.height - vertical) < 0.001)
        #expect(vertical <= 10.5, "the widest visible gap, at 70 % in compact density")
    }

    /// A banner or the fields between the floating buttons and the card: the gap above the card, inside the measured top.
    @Test func afterABannerOrTheFieldsTheCardKeepsTheGapAboveIt() {
        #expect(ComposerChrome.docked.gapAboveCard(hasPartsUnderHeader: true) == FloatingSpacing.gap)
        #expect(ComposerChrome.docked.gapAboveCard(hasPartsUnderHeader: false) == 0)
        #expect(ComposerChrome.sheet.gapAboveCard(hasPartsUnderHeader: true) == 0, "legacy's card has its own top inset")
    }

    /// A circle larger than its hit area (an accessibility size) has no slack: the bar's inset is the whole gap.
    @Test func aCircleThatOutgrowsItsHitAreaKeepsTheWholeGap() {
        let diameter: CGFloat = 48
        #expect(ComposerHeader.hitSlack(diameter: diameter) == .zero)
        let insets = ComposerChrome.docked.headerInsets(diameter: diameter)
        #expect(insets == EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
    }

    @Test func legacysChromeKeepsItsPaddings() {
        #expect(ComposerChrome.sheet.cardInsets == EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        let header = ComposerChrome.sheet.headerInsets(diameter: Self.defaultDiameter)
        #expect(header == EdgeInsets(top: 14, leading: 16, bottom: 6, trailing: 16))
    }

    /// The card's tools and its "Aa" bar keep 44 pt hit areas at the compact density and the smallest text too; legacy's row
    /// keeps its cells.
    @Test(arguments: composerSizes)
    func theCardsToolsKeep44PointHitAreas(size: ComposerSize) {
        let cell = size.metrics.cellSize
        #expect(ComposerControlRow.cellSize(cell, inCard: true) >= ComposerHeader.hitSize)
        #expect(ComposerControlRow.cellSize(cell, inCard: false) == cell)
    }

    /// A floating button's hit area is 44 pt whatever its glyph; it is drawn as the card tools' chip.
    @Test func theFloatingButtonIsDrawnAsTheCardToolsChip() {
        let capsule = ComposerHeader.capsuleSize(diameter: Self.defaultDiameter)
        #expect(capsule.width == Self.defaultDiameter)
        #expect(capsule.height == Self.defaultDiameter)
        #expect(capsule.width <= ComposerHeader.hitSize && capsule.height <= ComposerHeader.hitSize)
    }

    /// Variant D: a chip fits inside its cell, so neighbouring chips never touch and the cell stays the hit area.
    @Test(arguments: [ListDensity.regular, .compact])
    func aToolChipFitsInsideItsCellAroundItsGlyph(density: ListDensity) {
        let metrics = ComposerBarMetrics(density: density, scale: TextScale(percent: 100))
        let cell = ComposerControlRow.cellSize(metrics.cellSize, inCard: true)
        let diameter = ComposerChip.chipDiameter(cell: cell)
        #expect(diameter > metrics.glyphSize, "the glyph sits inside its chip")
        #expect(diameter < cell, "neighbouring chips never touch")
    }
}

/// One text size of the composer's chrome, for parameterised tests.
struct ComposerSize: Sendable, CustomTestStringConvertible {
    let density: ListDensity
    let percent: Int
    let dynamicType: CGFloat

    var metrics: ComposerBarMetrics {
        ComposerBarMetrics(density: density, scale: TextScale(percent: percent), dynamicType: dynamicType)
    }

    var testDescription: String { "\(density) \(percent) % ×\(dynamicType)" }
}
