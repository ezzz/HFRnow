import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing
import UIKit

@MainActor
struct OrientationPolicyTests {
    @Test func anIPadAlwaysRotates() {
        #expect(OrientationPolicy.supported(idiom: .pad, rotationAllowed: true) == .all)
        #expect(OrientationPolicy.supported(idiom: .pad, rotationAllowed: false) == .all)
    }

    @Test func anIPhoneRotatesWithoutUpsideDownUnlessLocked() {
        #expect(OrientationPolicy.supported(idiom: .phone, rotationAllowed: true) == .allButUpsideDown)
        #expect(OrientationPolicy.supported(idiom: .phone, rotationAllowed: false) == .portrait)
    }

    @Test func theMaskFollowsTheStoredSetting() {
        let locked = InMemorySettingsStore(["landscape_mode": .string("none")])
        #expect(OrientationPolicy.supported(idiom: .phone, store: locked) == .portrait)
        #expect(OrientationPolicy.supported(idiom: .phone, store: InMemorySettingsStore()) == .allButUpsideDown)
        // Legacy: any value but "none" allows rotation.
        let other = InMemorySettingsStore(["landscape_mode": .string("anything")])
        #expect(OrientationPolicy.supported(idiom: .phone, store: other) == .allButUpsideDown)
    }
}
