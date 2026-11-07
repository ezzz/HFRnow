@testable import SwiftHFR
import Testing

/// The composer bar's cell size: density × Dynamic Type × text scale (#598).
struct ComposerBarMetricsTests {
    @Test(arguments: [
        (ListDensity.regular, 100, 48.0), (.compact, 100, 40.0),
        (.regular, 70, 33.6), (.regular, 130, 62.4), (.compact, 70, 28.0), (.compact, 130, 52.0)
    ])
    func cellFollowsDensityAndScale(density: ListDensity, percent: Int, expected: Double) {
        let metrics = ComposerBarMetrics(density: density, scale: TextScale(percent: percent))
        #expect(abs(Double(metrics.cellSize) - expected) < 0.001)
        #expect(abs(Double(metrics.swatchSize) - expected / 2) < 0.001)
    }

    @Test(arguments: [
        (ListDensity.regular, 100, 2.0, 96.0), (.compact, 100, 1.5, 60.0), (.regular, 130, 2.0, 124.8), (.regular, 70, 0.9, 30.24)
    ])
    func cellGrowsWithDynamicType(density: ListDensity, percent: Int, dynamicType: Double, expected: Double) {
        let metrics = ComposerBarMetrics(density: density, scale: TextScale(percent: percent), dynamicType: dynamicType)
        #expect(abs(Double(metrics.cellSize) - expected) < 0.001)
        #expect(abs(Double(metrics.glyphSize) - expected * 0.4) < 0.001)
        #expect(abs(Double(metrics.swatchSize) - expected / 2) < 0.001)
    }
}
