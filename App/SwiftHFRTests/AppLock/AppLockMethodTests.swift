import HFRStorage
import LocalAuthentication
@testable import SwiftHFR
import Testing

/// The app-lock switch names the method the device has, never one it lacks (#1173, HIG › Managing accounts).
@MainActor
struct AppLockMethodTests {
    @Test(arguments: [
        (LABiometryType.faceID, "Verrouiller l’app (Face ID / code)"),
        (LABiometryType.touchID, "Verrouiller l’app (Touch ID / code)"),
        (LABiometryType.opticID, "Verrouiller l’app (Optic ID / code)"),
        (LABiometryType.none, "Verrouiller l’app (code)")
    ])
    func theSwitchNamesTheDevicesMethod(biometry: LABiometryType, title: String) {
        #expect(AppLockMethod(biometry: biometry).switchTitle == title)
    }

    /// The model asks its authenticator, so a Touch ID iPad shows « Touch ID » with no Face ID anywhere.
    @Test(arguments: [AppLockMethod.faceID, .touchID, .opticID, .codeOnly])
    func theModelTakesTheTitleFromTheAuthenticator(method: AppLockMethod) {
        let model = AppLockModel(store: InMemorySettingsStore(), authenticator: MethodAuthenticator(method: method))
        #expect(model.switchTitle == method.switchTitle)
    }

    @Test func theDeviceCodeAloneNeverMentionsABiometry() {
        let title = AppLockMethod.codeOnly.switchTitle
        #expect(!title.contains("Face ID") && !title.contains("Touch ID") && !title.contains("Optic ID"))
    }
}

/// An authenticator that only says which method the device has.
private struct MethodAuthenticator: DeviceOwnerAuthenticating {
    let method: AppLockMethod
    func availability() -> AppLockAvailability { .available }
    func authenticate(reason: String) async -> AppLockOutcome { .cancelled }
}
