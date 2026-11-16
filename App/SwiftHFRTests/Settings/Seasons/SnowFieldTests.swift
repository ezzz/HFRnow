import CoreGraphics
import Foundation
@testable import SwiftHFR
import Testing

/// Noël soft's falling snow (LOT-166): light, inside its area at every instant, the same on every launch.
struct SnowFieldTests {
    @Test(arguments: [0.0, 1.5, 17.25, 3600.0, 812_345_678.9])
    func everyFlakeStaysInsideTheArea(time: Double) {
        let size = CGSize(width: 390, height: 600)
        let points = SnowField.light.positions(at: time, in: size)
        #expect(points.count == SnowField.light.flakes.count)
        for point in points {
            #expect((0..<size.width).contains(point.x), "x \(point.x)")
            #expect((0..<size.height).contains(point.y), "y \(point.y)")
        }
    }

    @Test func theSnowIsLightSmallAndTheSameOnEveryLaunch() {
        let field = SnowField.light
        #expect(field.flakes.count <= 30)
        #expect(field.flakes.allSatisfy { $0.radius <= 3 && $0.opacity < 1 && $0.speed < 0.1 })
        let again = SnowField(count: 28, seed: 0x2512)
        #expect(again.positions(at: 42, in: CGSize(width: 100, height: 100))
            == field.positions(at: 42, in: CGSize(width: 100, height: 100)))
    }

    /// Flakes move with time, and a paused timeline (same date) draws the same frame.
    @Test func flakesFallWithTime() {
        let size = CGSize(width: 300, height: 300)
        let first = SnowField.light.positions(at: 10, in: size)
        let later = SnowField.light.positions(at: 10.5, in: size)
        #expect(first != later)
        #expect(SnowField.light.positions(at: 10, in: size) == first)
    }

    @Test func anEmptyAreaOrAnInvalidTimeDrawsNothing() {
        #expect(SnowField.light.positions(at: 1, in: .zero).isEmpty)
        #expect(SnowField.light.positions(at: .nan, in: CGSize(width: 10, height: 10)).isEmpty)
    }
}
