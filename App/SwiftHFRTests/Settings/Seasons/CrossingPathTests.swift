import CoreGraphics
import Foundation
@testable import SwiftHFR
import Testing

/// The line a crossing object follows (LOT-166, THEMES.md §4 rule 4, §6 rule 3): in by one edge, out by the opposite one, at
/// a random angle and direction, in at most 3 s, facing its travel.
@MainActor
struct CrossingPathTests {
    static let area = CGSize(width: 402, height: 650)
    static let object = CGSize(width: 64, height: 64)

    private func paths(directional: Bool, horizontalOnly: Bool, tilt: Double = .pi / 6, count: Int = 300) -> [CrossingPath] {
        let random = SeededRandom(42)
        return (0..<count).compactMap { _ in
            CrossingPath.random(
                in: Self.area, objectSize: Self.object, directional: directional, horizontalOnly: horizontalOnly,
                maxTilt: tilt, duration: 2.5, random: random
            )
        }
    }

    @Test func everyPathEntersByOneEdgeAndLeavesByTheOppositeOneFullyOutside() {
        let reach = hypot(Self.object.width, Self.object.height) / 2
        let all = paths(directional: false, horizontalOnly: false)
        #expect(all.count == 300)
        for path in all {
            let (from, to) = (path.start, path.end)
            switch path.entry {
            case .leading: #expect(from.x <= -reach + 0.001 && to.x >= Self.area.width + reach - 0.001)
            case .trailing: #expect(from.x >= Self.area.width + reach - 0.001 && to.x <= -reach + 0.001)
            case .top: #expect(from.y <= -reach + 0.001 && to.y >= Self.area.height + reach - 0.001)
            case .bottom: #expect(from.y >= Self.area.height + reach - 0.001 && to.y <= -reach + 0.001)
            }
            // Across the travel axis the object stays inside the area, at both ends.
            let horizontal = path.entry == .leading || path.entry == .trailing
            for point in [from, to] {
                let across = horizontal ? point.y : point.x
                let limit = horizontal ? Self.area.height : Self.area.width
                #expect(across >= 32 - 0.001 && across <= limit - 32 + 0.001)
            }
        }
        // Every edge is used: the direction is random.
        #expect(Set(all.map { "\($0.entry)" }) == ["leading", "trailing", "top", "bottom"])
    }

    @Test func theAngleIsRandomAndBounded() {
        let tilt = Double.pi / 6
        let angles = paths(directional: false, horizontalOnly: true, tilt: tilt).map { path in
            atan(abs(path.end.y - path.start.y) / abs(path.end.x - path.start.x))
        }
        #expect(angles.allSatisfy { $0 <= tilt + 1e-9 })
        // Spread over the range, not one fixed slope.
        #expect(Set(angles.map { Int($0 * 100) }).count > 20)
        #expect(angles.contains { $0 > tilt / 2 })
    }

    @Test func aCrossingLastsAtMostThreeSeconds() {
        let random = SeededRandom(7)
        let long = CrossingPath.random(
            in: Self.area, objectSize: Self.object, directional: true, horizontalOnly: true, maxTilt: 0.3, duration: 9,
            random: random
        )
        #expect(long?.duration == 3)
        #expect(paths(directional: false, horizontalOnly: false).allSatisfy { $0.duration <= CrossingPath.maxDuration })
    }

    /// The sleigh is drawn facing the trailing edge; mirrored as a whole and turned, it faces where it goes, both ways.
    @Test func directionalArtFacesItsTravel() {
        let all = paths(directional: true, horizontalOnly: true)
        #expect(all.contains { $0.mirrored } && all.contains { !$0.mirrored })
        for path in all {
            let dx = path.end.x - path.start.x
            let dy = path.end.y - path.start.y
            let length = hypot(dx, dy)
            #expect(abs(path.facing.dx - dx / length) < 1e-9)
            #expect(abs(path.facing.dy - dy / length) < 1e-9)
            #expect(path.mirrored == (dx < 0))
            // Never upside down: the turn stays within a quarter turn.
            #expect(abs(path.rotation) < .pi / 2)
        }
    }

    @Test func uprightArtIsNeitherMirroredNorTurned() {
        #expect(paths(directional: false, horizontalOnly: false).allSatisfy { !$0.mirrored && $0.rotation == 0 })
    }

    @Test func pointsFollowTheLineAndClamp() throws {
        let path = try #require(paths(directional: false, horizontalOnly: true, count: 1).first)
        func near(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool { hypot(lhs.x - rhs.x, lhs.y - rhs.y) < 1e-9 }
        #expect(near(path.point(at: 0), path.start))
        #expect(near(path.point(at: 1), path.end))
        #expect(near(path.point(at: 2), path.end))
        #expect(near(path.point(at: .nan), path.start))
        let middle = path.point(at: 0.5)
        #expect(abs(middle.x - (path.start.x + path.end.x) / 2) < 1e-9)
    }

    @Test func nothingForAnEmptyArea() {
        let random = SeededRandom(1)
        #expect(CrossingPath.random(
            in: .zero, objectSize: Self.object, directional: false, horizontalOnly: false, maxTilt: 0.3, duration: 2, random: random
        ) == nil)
    }
}
