import CoreGraphics
import Foundation
import HFRStorage
@testable import SwiftHFR
import Testing

/// What crosses Spooktober soft and arrives with it (LOT-191, THEMES.md §4 rule 4, §5): a witch, a ghost, a bat or a vampire on
/// the first launch; lightning, a ghost or a witch every 20–90 min; lightning is five flashes within 3 s. Clock and random numbers
/// are the tests' own: no waiting.
@MainActor
struct SamainCrossingTests {
    static let clear = SeasonalThemeModel.ScreenState()
    static let area = CGSize(width: 402, height: 650)
    let clock = SeasonTestClock(5, 10, 2027)
    let haptics = HapticRecorder()
    let scene = UUID()

    private func model(_ random: any SeasonalRandom) -> NoelCrossingModel {
        NoelCrossingModel(now: { clock.now }, random: random, haptics: haptics.feedback())
    }

    private func arrival(
        _ crossings: NoelCrossingModel, screen: SeasonalThemeModel.ScreenState = clear, animations: Bool = true
    ) -> NoelCrossingModel.Crossing? {
        crossings.crossing(
            for: scene, on: .init(area: Self.area, windowHeight: 874), screen: screen, animationsAllowed: animations,
            crossingsOn: false
        )
    }

    private func crossing(_ crossings: NoelCrossingModel, animations: Bool = true) -> NoelCrossingModel.Crossing? {
        crossings.crossing(
            for: scene, on: .init(area: Self.area, windowHeight: 874, items: SeasonalTheme.spooktoberSoft.crossingItems),
            screen: Self.clear, animationsAllowed: animations, crossingsOn: true
        )
    }

    // MARK: Arrival

    /// One of the four at random: the second random number of a model (after the first gap) picks.
    @Test(arguments: [0, 1, 2, 3])
    func theArrivalIsOneOfTheFourAtRandom(index: Int) throws {
        let crossings = model(ScriptedRandom([0, (Double(index) + 0.5) / 4, 0.3, 0.6]))
        crossings.sceneChanged(scene, active: true)
        crossings.queueArrival(items: NoelCrossingItem.samainArrival)
        let item = try #require(arrival(crossings))
        #expect(item.item == NoelCrossingItem.samainArrival[index])
        #expect(item.isArrival)
        #expect(item.flashes.isEmpty)
        #expect(!crossings.arrivalPending)
        #expect(item.path.duration <= CrossingPath.maxDuration)
        #expect(haptics.played == [.impact(.light)])
    }

    /// At least a fifth of the screen, « slightly bigger » (a quarter of the window, ≤ 240 pt), and never wider than the area.
    @Test(arguments: NoelCrossingItem.samainArrival)
    func theArrivalIsAQuarterOfTheWindowAndFitsTheWidth(item: NoelCrossingItem) {
        let size = NoelCrossingModel.arrivalSize(of: item, window: 874, areaWidth: Self.area.width)
        #expect(size.height <= 240)
        #expect(size.width <= Self.area.width * 0.8 + 0.001)
        #expect(abs(size.width / size.height - item.aspectRatio) < 1e-9)
        // Tall art keeps the full quarter: a ghost or a witch is at least a fifth of the window high.
        if item != .bat { #expect(size.height >= 874 / 5) }
        // The sleigh keeps its own rule whatever the width.
        let sleigh = NoelCrossingModel.arrivalSize(of: .sleigh, window: 874, areaWidth: 100)
        #expect(sleigh.height == NoelCrossingModel.arrivalHeight(window: 874))
    }

    @Test func theArrivalCrossesFromSideToSideAndFacesWhereItGoes() throws {
        for seed in 1...120 {
            let crossings = model(SeededRandom(UInt64(seed)))
            crossings.sceneChanged(scene, active: true)
            crossings.queueArrival(items: NoelCrossingItem.samainArrival)
            let item = try #require(arrival(crossings))
            let path = item.path
            #expect(path.entry == .leading || path.entry == .trailing)
            let travel = CGVector(dx: path.end.x - path.start.x, dy: path.end.y - path.start.y)
            if item.item == .witch {
                #expect(path.facesLeading)
                // The witch is drawn facing the leading edge: mirrored when she goes to the trailing one.
                #expect(path.mirrored == (travel.dx > 0))
                #expect(path.facing.dx * travel.dx + path.facing.dy * travel.dy > 0, "seed \(seed)")
            } else {
                // A ghost, a bat or a vampire has no front: upright.
                #expect(!path.mirrored && path.rotation == 0)
            }
        }
    }

    /// Reduce Motion or « Animations de saison » off: nothing is played and the arrival is dropped, so the alert comes alone.
    @Test func withoutAnimationsTheArrivalIsDroppedWithoutAHaptic() {
        let crossings = model(SeededRandom(3))
        crossings.sceneChanged(scene, active: true)
        crossings.queueArrival(items: NoelCrossingItem.samainArrival)
        #expect(arrival(crossings, animations: false) == nil)
        #expect(!crossings.arrivalPending)
        #expect(haptics.played.isEmpty)
    }

    @Test func theArrivalWaitsForAClearScreen() {
        let crossings = model(SeededRandom(3))
        crossings.sceneChanged(scene, active: true)
        crossings.queueArrival(items: NoelCrossingItem.samainArrival)
        #expect(arrival(crossings, screen: .init(isKeyboardVisible: true)) == nil)
        #expect(crossings.arrivalPending)
        #expect(arrival(crossings) != nil)
    }

    // MARK: Crossing items

    @Test func spooktoberSoftCrossesWithLightningAGhostOrAWitch() {
        #expect(SeasonalTheme.spooktoberSoft.crossingItems == [.lightning, .ghost, .witch])
        #expect(SeasonalTheme.spooktoberSoft.hasCrossings)
        #expect(!SeasonalTheme.spooktoberAbuse.hasCrossings)
        #expect(SeasonalTheme.noelSoft.crossingItems == NoelCrossingItem.crossing)
        let crossings = model(ScriptedRandom([0]))
        #expect(crossings.shouldWatch(scene: scene, theme: .spooktoberSoft))
        #expect(!crossings.shouldWatch(scene: scene, theme: .spooktoberAbuse))
        #expect(!crossings.shouldWatch(scene: scene, theme: nil))
    }

    @Test func everyItemOfThePoolCrossesInTimeAndNoneBeforeTwentyMinutes() {
        var seen: Set<NoelCrossingItem> = []
        for seed in 1...60 {
            let crossings = model(SeededRandom(UInt64(seed)))
            crossings.sceneChanged(scene, active: true)
            clock.now += 19 * 60
            #expect(crossing(crossings) == nil)
            clock.now += 71 * 60
            guard let item = crossing(crossings) else {
                Issue.record("nothing crossed after 90 min, seed \(seed)")
                continue
            }
            seen.insert(item.item)
            #expect(!item.isArrival)
            #expect(crossings.nextGap >= 20 * 60)
            crossings.finish(item.id)
        }
        #expect(seen == [.lightning, .ghost, .witch])
    }

    // MARK: Lightning

    /// Five flashes of about 0.3 s, at random places, all within 3 s, then one light haptic for the whole crossing.
    @Test func lightningIsFiveFlashesWithinThreeSeconds() throws {
        // First gap 0, then the pick 0 (lightning is the first item of the pool).
        let crossings = model(ScriptedRandom([0, 0, 0.7, 0.2, 0.9, 0.4, 0.1]))
        crossings.sceneChanged(scene, active: true)
        clock.now += 21 * 60
        let strike = try #require(crossing(crossings))
        #expect(strike.item == .lightning)
        #expect(strike.flashes.count == 5)
        #expect(strike.path.duration == LightningStrike.window)
        #expect(LightningStrike.window <= 3)
        var previousEnd = 0.0
        for flash in strike.flashes {
            #expect(abs(flash.duration - 0.3) < 1e-9)
            #expect(flash.start >= previousEnd - 1e-9)
            previousEnd = flash.start + flash.duration
            #expect(previousEnd <= 3 + 1e-9)
            // The whole bolt stays inside the band.
            let bolt = CGRect(
                x: flash.center.x - strike.size.width / 2, y: flash.center.y - strike.size.height / 2,
                width: strike.size.width, height: strike.size.height
            )
            #expect(CGRect(origin: .zero, size: Self.area).insetBy(dx: -0.001, dy: -0.001).contains(bolt))
        }
        #expect(haptics.played == [.impact(.light)])
    }

    @Test func theFlashesAreAtRandomPlacesAndNeverOverlapAcrossSeeds() {
        var places: Set<CGPoint> = []
        for seed in 1...50 {
            let flashes = LightningStrike.flashes(in: Self.area, size: CGSize(width: 57, height: 120), random: SeededRandom(UInt64(seed)))
            #expect(flashes.count == LightningStrike.flashCount)
            for (before, after) in zip(flashes, flashes.dropFirst()) { #expect(before.start + before.duration <= after.start + 1e-9) }
            #expect(flashes.allSatisfy { $0.start >= 0 && $0.start + $0.duration <= 3 + 1e-9 })
            places.formUnion(flashes.map(\.center))
        }
        #expect(places.count > 150)
    }

    @Test func aFlashIsVisibleOnlyDuringItsOwnTime() throws {
        let flashes = LightningStrike.flashes(in: Self.area, size: CGSize(width: 57, height: 120), random: SeededRandom(7))
        for flash in flashes {
            #expect(LightningStrike.visibleFlash(at: flash.start + 0.1, in: flashes) == flash)
            #expect(LightningStrike.visibleFlash(at: flash.start + flash.duration + 1e-6, in: flashes) != flash)
        }
        #expect(LightningStrike.visibleFlash(at: 3.01, in: flashes) == nil)
        let gap = try #require(zip(flashes, flashes.dropFirst()).first { $0.1.start - ($0.0.start + $0.0.duration) > 0.01 })
        #expect(LightningStrike.visibleFlash(at: gap.0.start + gap.0.duration + 0.005, in: flashes) == nil)
        #expect(LightningStrike.flashes(in: .zero, size: CGSize(width: 57, height: 120), random: SeededRandom(1)).isEmpty)
    }

    /// Reduce Motion: no flash, no haptic.
    @Test func noLightningWithoutAnimations() {
        let crossings = model(ScriptedRandom([0]))
        crossings.sceneChanged(scene, active: true)
        clock.now += 30 * 60
        #expect(crossing(crossings, animations: false) == nil)
        #expect(haptics.played.isEmpty)
    }

    // MARK: Facing

    /// Art drawn facing the leading edge turns to face where it goes: mirrored as a whole going the other way.
    @Test func artFacingTheLeadingEdgeFacesItsTravel() throws {
        for seed in 1...100 {
            let traits = CrossingPath.Traits(
                size: CGSize(width: 90, height: 72), directional: true, facesLeading: true, horizontalOnly: false,
                maxTilt: .pi / 6, duration: 3
            )
            let path = try #require(CrossingPath.random(in: Self.area, for: traits, random: SeededRandom(UInt64(seed))))
            let travel = CGVector(dx: path.end.x - path.start.x, dy: path.end.y - path.start.y)
            let length = hypot(travel.dx, travel.dy)
            let dot = (path.facing.dx * travel.dx + path.facing.dy * travel.dy) / length
            #expect(dot > 0.99, "seed \(seed)")
        }
    }

    /// The sleigh, drawn facing the trailing edge, is unchanged.
    @Test func artFacingTheTrailingEdgeStillFacesItsTravel() throws {
        for seed in 1...100 {
            let traits = CrossingPath.Traits(
                size: CGSize(width: 180, height: 64), directional: true, horizontalOnly: false, maxTilt: .pi / 6, duration: 3
            )
            let path = try #require(CrossingPath.random(in: Self.area, for: traits, random: SeededRandom(UInt64(seed))))
            let travel = CGVector(dx: path.end.x - path.start.x, dy: path.end.y - path.start.y)
            #expect(!path.facesLeading)
            #expect((path.facing.dx * travel.dx + path.facing.dy * travel.dy) / hypot(travel.dx, travel.dy) > 0.99)
        }
    }
}
