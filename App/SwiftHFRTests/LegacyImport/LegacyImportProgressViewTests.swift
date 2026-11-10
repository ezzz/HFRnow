@testable import SwiftHFR
import Testing
import UIKit

/// #754: the import screen animates while it runs and is still under Reduce Motion.
@MainActor
struct LegacyImportProgressViewTests {
    typealias Screen = LegacyImportProgressView

    @Test func theAnimatedWorkerAnimatesWhileTheImportRuns() {
        #expect(Screen.display(for: .animatedWorker, reduceMotion: false) == .animated)
    }

    @Test func reduceMotionGivesTheStillDrawingAndAProgressIndicator() {
        #expect(Screen.display(for: .animatedWorker, reduceMotion: true) == .staticWithIndicator)
        #expect(Screen.display(for: .staticWorker, reduceMotion: true) == .staticWithIndicator)
    }

    @Test func theStaticVariantNeverMoves() {
        #expect(Screen.display(for: .staticWorker, reduceMotion: false) == .staticWithIndicator)
    }

    @Test func theLoopRaisesStrikesSparksAndReturns() {
        #expect(Screen.pose(at: 0) == .init(angle: 0, spark: 0))
        let strike = Screen.pose(at: Screen.period * 0.585)
        #expect(abs(strike.angle - Screen.impactAngle) < 0.001)
        #expect(strike.spark > 0.9)
        #expect(Screen.pose(at: Screen.period * 0.65).spark > 0)
        #expect(Screen.pose(at: Screen.period * 0.85).angle > 0)
        #expect(Screen.pose(at: Screen.period * 0.85).angle < Screen.impactAngle)
        // One period later it starts again.
        #expect(Screen.pose(at: Screen.period + 0.1) == Screen.pose(at: 0.1))
    }

    @Test func theStillPoseIsBetweenRaisedAndStruck() {
        #expect(Screen.restAngle > 0 && Screen.restAngle < Screen.impactAngle)
    }

    @Test func everyLayerIsInTheAssetCatalogue() {
        for name in ["ImportWorkerBody", "ImportWorkerArm", "ImportWorkerSpark"] {
            #expect(UIImage(named: name) != nil, "\(name)")
        }
    }
}
