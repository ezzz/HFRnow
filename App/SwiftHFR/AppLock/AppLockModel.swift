import Foundation
import HFRStorage
import Observation
import SwiftUI

/// How long the app may stay in the background before it locks again (`app_lock_grace_seconds`).
enum AppLockGrace: Int, CaseIterable, Sendable {
    case immediately = 0
    case oneMinute = 60
    case fiveMinutes = 300

    /// Picker label.
    var title: String {
        switch self {
        case .immediately: "Immédiatement"
        case .oneMinute: "Après 1 minute"
        case .fiveMinutes: "Après 5 minutes"
        }
    }
}

/// Whether the device can run the lock's authentication.
enum AppLockAvailability: Sendable, Equatable {
    /// Biometrics or the device passcode can be asked.
    case available
    /// The device has no passcode: there is nothing to lock with.
    case passcodeNotSet
    /// Anything else (policy refused by a profile, for example).
    case unavailable
}

/// How one authentication ended.
enum AppLockOutcome: Sendable, Equatable {
    case success
    /// The user, the app or the system cancelled the sheet.
    case cancelled
    case failed
    /// The passcode was removed since the lock was turned on.
    case passcodeNotSet
}

/// Asks the device owner to authenticate (`LAContext`, policy `deviceOwnerAuthentication`); a scripted double in tests.
protocol DeviceOwnerAuthenticating: Sendable {
    /// Whether the policy can be evaluated now.
    func availability() -> AppLockAvailability
    /// Shows the system sheet (Face ID or Touch ID, then the device code) with `reason`.
    func authenticate(reason: String) async -> AppLockOutcome
}

// New in SwiftHFR: none @ 87fe0d1c (legacy has no app lock; GAP-169). Differences: the whole feature.
/// The optional Face ID / code lock of the app (LOT-173, ADR 0013 §6), one instance for every scene.
///
/// UI only: nothing in the engine waits on it, so the background MP check and the session checks run while the app is locked.
/// Locks at launch and when the app comes back after the grace delay in the **background** (`inactive` alone, such as
/// the authentication sheet itself or Control Center, never locks). While the option is on, every scene is covered when
/// the app is not active, so the app switcher snapshot shows the cover, not the content.
@MainActor
@Observable
final class AppLockModel {
    /// The settings switch.
    private(set) var isEnabled: Bool
    /// Time in the background before locking again.
    var grace: AppLockGrace {
        didSet { if grace != oldValue { store.set(grace.rawValue, for: SettingKey.appLockGraceSeconds) } }
    }
    /// True until the owner authenticates.
    private(set) var isLocked: Bool
    /// True while the system sheet is up.
    private(set) var isAuthenticating = false
    /// Why the cover is still there (a failed authentication) or why the switch did not turn on; nil when nothing to say.
    private(set) var message: String?
    /// Whether the app is in the foreground and active.
    private(set) var isActive = true

    /// Whether every scene shows the cover instead of the app.
    var isCovered: Bool { isEnabled && (isLocked || !isActive) }

    @ObservationIgnored private let store: any SettingsStore
    @ObservationIgnored private let authenticator: any DeviceOwnerAuthenticating
    /// On the monotonic clock that counts sleep: setting the device clock cannot shorten the time away (a reboot relaunches
    /// the app, locked).
    @ObservationIgnored private var backgroundedAt: ContinuousClock.Instant?
    /// One automatic authentication per lock: never again after a failure or a cancel, or the sheet would loop with the
    /// scene phase it changes.
    @ObservationIgnored private var promptsByItself = false

    /// The reason the system sheet shows.
    static let reason = "Déverrouiller HFR"

    /// Reads the settings; the app starts locked when the option is on.
    init(store: any SettingsStore, authenticator: any DeviceOwnerAuthenticating) {
        self.store = store
        self.authenticator = authenticator
        // A local: `self.isEnabled` cannot be read before every stored property is initialized.
        let enabled = store.value(for: SettingKey.appLockEnabled)
        isEnabled = enabled
        grace = AppLockGrace(rawValue: store.value(for: SettingKey.appLockGraceSeconds)) ?? .immediately
        isLocked = enabled
        promptsByItself = enabled
    }

    /// Turns the option on or off; on only when the device can authenticate its owner (else `message` says why).
    /// Turning it on does not lock at once.
    func setEnabled(_ enabled: Bool) {
        message = nil
        if enabled {
            switch authenticator.availability() {
            case .available:
                break
            case .passcodeNotSet:
                message = "Définissez un code sur l’appareil pour utiliser le verrouillage."
                return
            case .unavailable:
                message = "Le verrouillage n’est pas disponible sur cet appareil."
                return
            }
        }
        isEnabled = enabled
        store.set(enabled, for: SettingKey.appLockEnabled)
        if !enabled {
            isLocked = false
            backgroundedAt = nil
        }
    }

    /// Follows the app's scene phase. Returns true when the caller should start the authentication now (the app became
    /// active, locked, and has not asked by itself yet for this lock).
    @discardableResult
    func scenePhaseChanged(to phase: ScenePhase, now: ContinuousClock.Instant = ContinuousClock.now) -> Bool {
        switch phase {
        case .background:
            isActive = false
            if backgroundedAt == nil { backgroundedAt = now }
            return false
        case .active:
            isActive = true
            if isEnabled, let backgroundedAt {
                let away = backgroundedAt.duration(to: now)
                // A negative time cannot happen on this clock; if it ever did, it locks (fail closed).
                if away < .zero || away >= .seconds(grace.rawValue) { lock() }
            }
            backgroundedAt = nil
            guard isLocked, promptsByItself, !isAuthenticating else { return false }
            promptsByItself = false
            return true
        default:
            isActive = false
            return false
        }
    }

    /// Asks the owner to authenticate; a failure or a cancel keeps the cover. A device whose passcode was removed unlocks:
    /// the lock has nothing left to rely on (spec D6).
    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        message = nil
        let outcome = await authenticator.authenticate(reason: Self.reason)
        isAuthenticating = false
        switch outcome {
        case .success, .passcodeNotSet:
            isLocked = false
        case .cancelled:
            break
        case .failed:
            message = "Authentification échouée. Réessayez."
        }
    }

    private func lock() {
        guard !isLocked else { return }
        isLocked = true
        promptsByItself = true
        message = nil
    }
}

extension AppLockModel {
    /// A model for SwiftUI previews: option off, and no system sheet ever shown.
    static func preview() -> AppLockModel {
        AppLockModel(store: InMemorySettingsStore(), authenticator: NoAuthentication())
    }
}

/// Never shows a system sheet (previews).
private struct NoAuthentication: DeviceOwnerAuthenticating {
    func availability() -> AppLockAvailability { .available }
    func authenticate(reason: String) async -> AppLockOutcome { .cancelled }
}
