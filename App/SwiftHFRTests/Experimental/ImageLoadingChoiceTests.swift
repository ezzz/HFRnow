import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// Réglages › Expérimental › « Chargement des images » (#902), first activation (#1003, operator 2026-11-17: « forcer
/// toujours »): the first time the option is turned on, the choice starts at « Toujours » whatever an earlier beta stored;
/// later activations keep what the member chose while it was on.
@MainActor
struct ImageLoadingChoiceTests {
    /// A beta stored « Jamais »: the first activation starts at « Toujours », and images load.
    @Test func theFirstActivationStartsAtToujours() {
        let store = InMemorySettingsStore()
        store.set(ImageDisplayMode.never, for: SettingKey.displayImages)
        let settings = ExperimentalSettings(store: store)
        settings.set(.imageLoadingChoice, isOn: true)
        #expect(store.value(for: SettingKey.displayImages) == .always)
        #expect(ImageLoadingChoice.autoLoad(store: store) == .always, "images load")
        #expect(store.value(for: SettingKey.experimentalImageLoadingChoiceStarted))
    }

    /// The member picks « Wi-Fi uniquement », turns the option off, then on again: the choice is kept, in the same session
    /// and after a relaunch (a new `ExperimentalSettings` over the same store).
    @Test func laterActivationsKeepTheMembersChoice() {
        let store = InMemorySettingsStore()
        let settings = ExperimentalSettings(store: store)
        settings.set(.imageLoadingChoice, isOn: true)
        store.set(ImageDisplayMode.wifiOnly, for: SettingKey.displayImages) // the picker's write
        settings.set(.imageLoadingChoice, isOn: false)
        settings.set(.imageLoadingChoice, isOn: true)
        #expect(store.value(for: SettingKey.displayImages) == .wifiOnly)
        let relaunched = ExperimentalSettings(store: store)
        relaunched.set(.imageLoadingChoice, isOn: false)
        relaunched.set(.imageLoadingChoice, isOn: true)
        #expect(store.value(for: SettingKey.displayImages) == .wifiOnly)
    }

    /// A member who toggled the option in a build before #1003 (switch stored, no started flag) still gets « Toujours » at
    /// their first activation after the update.
    @Test func anActivationBeforeTheUpdateDoesNotCount() {
        let store = InMemorySettingsStore()
        store.set(false, for: SettingKey.experimentalImageLoadingChoice)
        store.set(ImageDisplayMode.never, for: SettingKey.displayImages)
        ExperimentalSettings(store: store).set(.imageLoadingChoice, isOn: true)
        #expect(store.value(for: SettingKey.displayImages) == .always)
    }

    /// Only this option's activation touches the image choice; turning it off changes nothing.
    @Test func otherSwitchesAndTurningOffLeaveTheChoiceAlone() {
        let store = InMemorySettingsStore()
        store.set(ImageDisplayMode.never, for: SettingKey.displayImages)
        let settings = ExperimentalSettings(store: store)
        settings.set(.modernComposer, isOn: true)
        settings.set(.imageLoadingChoice, isOn: false)
        #expect(store.value(for: SettingKey.displayImages) == .never)
        #expect(!store.value(for: SettingKey.experimentalImageLoadingChoiceStarted))
    }
}
