@testable import SwiftHFR
import Testing

/// The composer bar's cell size: density × text scale (#598).
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
}
