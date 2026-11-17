import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// Réglages › Expérimental › « Chargement des images » (#902), first activation (#1003, operator 2026-11-17: « forcer
/// toujours »): the first time the option is turned on, the choice starts at « Toujours » whatever an earlier beta stored;
/// later activations keep what the member chose while it was on.
@MainActor
struct ImageLoadingChoiceTests {
    /// A beta stored « Jamais » (or « Wi-Fi uniquement »): the first activation starts at « Toujours », and images load.
    @Test(arguments: [ImageDisplayMode.never, .wifiOnly])
    func theFirstActivationStartsAtToujours(stored: ImageDisplayMode) {
        let store = InMemorySettingsStore()
        store.set(stored, for: SettingKey.displayImages)
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

    /// A member who used the option in a build before #1003 (switch stored, off or still on, no started flag) gets « Toujours »
    /// at their first activation after the update, as #1003's persistence point says, even over a choice made while the
    /// option was on in that build (open question to the operator on #1004).
    @Test(arguments: [false, true])
    func anActivationBeforeTheUpdateDoesNotCount(wasOn: Bool) {
        let store = InMemorySettingsStore()
        store.set(wasOn, for: SettingKey.experimentalImageLoadingChoice)
        store.set(ImageDisplayMode.wifiOnly, for: SettingKey.displayImages)
        let settings = ExperimentalSettings(store: store)
        if wasOn { settings.set(.imageLoadingChoice, isOn: false) }
        #expect(store.value(for: SettingKey.displayImages) == .wifiOnly, "turning off keeps it")
        settings.set(.imageLoadingChoice, isOn: true)
        #expect(store.value(for: SettingKey.displayImages) == .always)
    }

    /// The reader reads the switch and the choice off the main actor: after every write of an activation it sees either the
    /// option off (always) or the option on with « Toujours », never the option on with the stale « Jamais ».
    @Test func theReaderNeverSeesTheOptionOnWithTheStaleChoice() {
        let store = AutoLoadSpyStore()
        store.set(ImageDisplayMode.never, for: SettingKey.displayImages)
        store.seen.removeAll()
        ExperimentalSettings(store: store).set(.imageLoadingChoice, isOn: true)
        #expect(!store.seen.isEmpty)
        #expect(store.seen.allSatisfy { $0 == .always }, "\(store.seen)")
    }

    /// Only this option's activation touches the image choice; turning it off changes nothing.
    @Test func otherSwitchesAndTurningOffLeaveTheChoiceAlone() {
        let store = InMemorySettingsStore()
        store.set(true, for: SettingKey.experimentalImageLoadingChoice) // on, so turning it off really runs
        store.set(ImageDisplayMode.never, for: SettingKey.displayImages)
        let settings = ExperimentalSettings(store: store)
        settings.set(.modernComposer, isOn: true)
        settings.set(.imageLoadingChoice, isOn: false)
        #expect(store.value(for: SettingKey.displayImages) == .never)
        #expect(!store.value(for: SettingKey.experimentalImageLoadingChoiceStarted))
    }
}

/// An in-memory store that records the reader's image mode after every write (`ImageLoadingChoice.autoLoad`).
private final class AutoLoadSpyStore: SettingsStore, @unchecked Sendable {
    private let base = InMemorySettingsStore()
    // Written and read on the test's main actor only.
    var seen: [ImageAutoLoad] = []

    func rawValue(forKey key: String) -> SettingRawValue? { base.rawValue(forKey: key) }

    func setRawValue(_ value: SettingRawValue, forKey key: String) {
        base.setRawValue(value, forKey: key)
        seen.append(ImageLoadingChoice.autoLoad(store: self))
    }

    func removeValue(forKey key: String) {
        base.removeValue(forKey: key)
        seen.append(ImageLoadingChoice.autoLoad(store: self))
    }
}
