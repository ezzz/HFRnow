import Foundation
import HFRStorage
@testable import SwiftHFR
import Synchronization
import SwiftUI
import Testing

/// Answers each authentication from a script and counts the sheets shown.
private final class ScriptedAuthenticator: DeviceOwnerAuthenticating {
    private let state: Mutex<(outcomes: [AppLockOutcome], sheets: Int)>
    let availabilityValue: AppLockAvailability

    init(_ outcomes: [AppLockOutcome] = [], availability: AppLockAvailability = .available) {
        state = Mutex((outcomes, 0))
        availabilityValue = availability
    }

    var sheets: Int { state.withLock { $0.sheets } }

    func availability() -> AppLockAvailability { availabilityValue }

    func authenticate(reason: String) async -> AppLockOutcome {
        state.withLock { state in
            state.sheets += 1
            return state.outcomes.isEmpty ? .cancelled : state.outcomes.removeFirst()
        }
    }
}

@MainActor
struct AppLockModelTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    private func model(
        enabled: Bool = true, grace: Int = 0, _ authenticator: ScriptedAuthenticator = ScriptedAuthenticator()
    ) -> (AppLockModel, InMemorySettingsStore) {
        let store = InMemorySettingsStore()
        store.set(enabled, for: SettingKey.appLockEnabled)
        store.set(grace, for: SettingKey.appLockGraceSeconds)
        return (AppLockModel(store: store, authenticator: authenticator), store)
    }

    @Test func offByDefaultNothingIsEverCovered() {
        let lock = AppLockModel(store: InMemorySettingsStore(), authenticator: ScriptedAuthenticator())
        #expect(!lock.isEnabled)
        #expect(!lock.isCovered)
        #expect(!lock.scenePhaseChanged(to: .active, now: start))
        lock.scenePhaseChanged(to: .background, now: start)
        #expect(!lock.isCovered)
        #expect(!lock.scenePhaseChanged(to: .active, now: start.addingTimeInterval(3_600)))
        #expect(!lock.isLocked)
    }

    @Test func locksAtLaunchAndAsksByItselfOnce() async {
        let authenticator = ScriptedAuthenticator([.success])
        let (lock, _) = model(authenticator)
        #expect(lock.isLocked && lock.isCovered)
        #expect(lock.scenePhaseChanged(to: .active, now: start))
        // The sheet makes the app inactive then active again: no second automatic sheet.
        lock.scenePhaseChanged(to: .inactive, now: start)
        #expect(!lock.scenePhaseChanged(to: .active, now: start))
        await lock.unlock()
        #expect(!lock.isLocked)
        #expect(!lock.isCovered)
        #expect(authenticator.sheets == 1)
    }

    @Test(arguments: [AppLockOutcome.cancelled, .failed])
    func aFailedOrCancelledAuthenticationKeepsTheCoverAndNeverRetriesByItself(outcome: AppLockOutcome) async {
        let authenticator = ScriptedAuthenticator([outcome])
        let (lock, _) = model(authenticator)
        #expect(lock.scenePhaseChanged(to: .active, now: start))
        await lock.unlock()
        #expect(lock.isLocked && lock.isCovered)
        #expect((lock.message != nil) == (outcome == .failed))
        lock.scenePhaseChanged(to: .inactive, now: start)
        #expect(!lock.scenePhaseChanged(to: .active, now: start))
        #expect(authenticator.sheets == 1)
    }

    @Test func aDeviceWhosePasscodeWasRemovedUnlocks() async {
        let (lock, _) = model(ScriptedAuthenticator([.passcodeNotSet]))
        await lock.unlock()
        #expect(!lock.isLocked)
        #expect(lock.isEnabled)
    }

    @Test(arguments: [(0, 0.0, true), (60, 59.0, false), (60, 60.0, true), (300, 299.0, false), (300, 300.0, true)])
    func locksAgainOnlyAfterTheGraceDelayInTheBackground(grace: Int, away: TimeInterval, locks: Bool) async {
        let (lock, _) = model(grace: grace, ScriptedAuthenticator([.success]))
        await lock.unlock()
        lock.scenePhaseChanged(to: .inactive, now: start)
        lock.scenePhaseChanged(to: .background, now: start)
        #expect(lock.isCovered)
        let asks = lock.scenePhaseChanged(to: .active, now: start.addingTimeInterval(away))
        #expect(lock.isLocked == locks)
        #expect(asks == locks)
        #expect(lock.isCovered == locks)
    }

    /// The device clock set back while the app was away: elapsed time is negative, the app locks anyway.
    @Test func aClockSetBackWhileAwayLocks() async {
        let (lock, _) = model(grace: 300, ScriptedAuthenticator([.success]))
        await lock.unlock()
        lock.scenePhaseChanged(to: .background, now: start)
        #expect(lock.scenePhaseChanged(to: .active, now: start.addingTimeInterval(-3_600)))
        #expect(lock.isLocked)
    }

    @Test func inactiveAloneCoversButNeverLocks() async {
        let (lock, _) = model(ScriptedAuthenticator([.success]))
        await lock.unlock()
        lock.scenePhaseChanged(to: .inactive, now: start)
        #expect(lock.isCovered)
        #expect(!lock.isLocked)
        #expect(!lock.scenePhaseChanged(to: .active, now: start.addingTimeInterval(3_600)))
        #expect(!lock.isCovered)
    }

    @Test func turningOnNeedsAPasscodeAndDoesNotLockAtOnce() {
        let refused = AppLockModel(store: InMemorySettingsStore(), authenticator: ScriptedAuthenticator(availability: .passcodeNotSet))
        refused.setEnabled(true)
        #expect(!refused.isEnabled)
        #expect(refused.message != nil)

        let store = InMemorySettingsStore()
        let lock = AppLockModel(store: store, authenticator: ScriptedAuthenticator())
        lock.setEnabled(true)
        #expect(lock.isEnabled)
        #expect(!lock.isLocked)
        #expect(store.value(for: SettingKey.appLockEnabled))
    }

    @Test func theGraceDelayIsStoredAndAnUnknownValueReadsAsImmediately() {
        let (lock, store) = model(grace: 60)
        #expect(lock.grace == .oneMinute)
        lock.grace = .fiveMinutes
        #expect(store.value(for: SettingKey.appLockGraceSeconds) == 300)
        store.setRawValue(.int(42), forKey: SettingKey.appLockGraceSeconds.key)
        #expect(AppLockModel(store: store, authenticator: ScriptedAuthenticator()).grace == .immediately)
    }

    @Test func turningOffUncoversAtOnce() {
        let (lock, _) = model()
        lock.setEnabled(false)
        #expect(!lock.isLocked)
        #expect(!lock.isCovered)
    }
}
