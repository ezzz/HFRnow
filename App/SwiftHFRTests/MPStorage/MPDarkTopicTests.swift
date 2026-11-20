import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// « MP multiples → dark topic » as its own experimental option (#1014), replacing #859's per-function switches: the gate, the
/// carry-over of the retired per-account switch, and the words.
@MainActor
struct MPDarkTopicTests {
    private typealias Base = MPStorageSyncModelTests

    // MARK: The option

    @Test func theOptionIsListedUnderMessagesAndOffByDefault() {
        #expect(ExperimentalTheme.messages.listedFeatures == [.mpDarkTopic])
        #expect(ExperimentalFeature.mpDarkTopic.issue == 1014)
        #expect(!ExperimentalSettings(store: InMemorySettingsStore()).isOn(.mpDarkTopic))
        #expect(!ExperimentalSettings.isOn(.mpDarkTopic, in: nil))
    }

    /// #1128 (replacing #1014's choice of 2026-11-17): the option works like the others, its description behind the ⓘ. The page
    /// builds every listed option as an `ExperimentalFeatureRow`, so this one has a title and an explanation for that ⓘ to show.
    @Test func theDarkTopicIsAnOrdinaryOptionWithAnExplanationForItsIcon() {
        #expect(ExperimentalFeature.mpDarkTopic.title == "MP multiples → dark topic")
        #expect(ExperimentalFeature.mpDarkTopic.explanation == MPDarkTopic.explanation)
        #expect(MPDarkTopic.explanation.contains("Désactivé"))
        #expect(ExperimentalPageLayout.groups().flatMap(\.features).contains(.mpDarkTopic))
    }

    // MARK: The gate

    /// Off (the default): the positions are not read, and everything else of the storage works as legacy's single switch says.
    @Test func withTheOptionOffOnlyTheDarkTopicIsOff() async throws {
        let text = try Base.flagged([MPStorageMPFlag(topic: 31, pValue: "1", href: "t555", page: 2)])
        let fixture = try await Base.make(
            thread: 7, state: .on, copy: MPStorageCopy(post: 7, base: text), text: text, darkTopic: false
        )
        await fixture.model.start()
        #expect(!fixture.model.isEnabled(.mpFlags))
        #expect(fixture.model.isEnabled(.ignoreList) && fixture.model.isEnabled(.bookmarks))
        #expect(fixture.model.flag(for: messageThread(31, group: true)) == nil)
        #expect(fixture.model.document(for: .ignoreList) != nil)
        #expect(fixture.model.writeConsent(for: .ignoreList) == .sync)
        let changed = await fixture.model.edit(.ignoreList) { document, stamp in
            try document.addBlocklistEntry(username: "user9", stamp: stamp)
        }
        #expect(changed)
    }

    @Test func withTheOptionOnTheFlagsShow() async throws {
        let text = try Base.flagged([MPStorageMPFlag(topic: 31, pValue: "1", href: "t555", page: 2)])
        let fixture = try await Base.make(thread: 7, state: .on, copy: MPStorageCopy(post: 7, base: text), text: text)
        await fixture.model.start()
        #expect(fixture.model.isEnabled(.mpFlags))
        #expect(fixture.model.flag(for: messageThread(31, group: true))?.href == "t555")
    }

    @Test func withoutAnExperimentalEnvironmentTheOptionReadsOff() async throws {
        let fixture = try await Base.make(thread: 7, state: .on)
        fixture.model.experimental = nil
        #expect(!fixture.model.isEnabled(.mpFlags))
        #expect(fixture.model.isEnabled(.bookmarks))
    }

    /// Without the account's record nothing is on, whatever the option says.
    @Test func anUnreadableRecordTurnsEveryFunctionOff() async throws {
        let fixture = try await Base.make(thread: 7)
        fixture.settings.setRawValue(.string("paused"), forKey: "mpstorage.alice") // written by a newer build
        fixture.model.reloadRecord()
        #expect(fixture.model.record == nil)
        for function in MPStorageFunction.allCases { #expect(!fixture.model.isEnabled(function)) }
    }

    // MARK: The retired per-account switch (#859)

    /// A member who had switched « dark topic » off for this account keeps it off, and the retired entry never blocks the
    /// option again: it goes with the carry-over.
    @Test func aRetiredPerAccountSwitchOffKeepsTheDarkTopicOffOnce() async throws {
        let fixture = try await Base.make(thread: 7, state: .on)
        _ = fixture.states.setFunction(.mpFlags, enabled: false, for: Base.account)
        fixture.model.reloadRecord()
        let settings = ExperimentalSettings(store: InMemorySettingsStore())
        settings.set(.mpDarkTopic, isOn: true) // the launch migration moved the #859 option here
        fixture.model.experimental = settings
        #expect(!settings.isOn(.mpDarkTopic))
        #expect(!fixture.model.isEnabled(.mpFlags))
        #expect(fixture.states.record(for: Base.account)?.isEnabled(.mpFlags) == true)
        #expect(fixture.states.record(for: Base.account)?.state == .on)
        // Turned on again by the member: the entry is gone, so the next assignment changes nothing.
        settings.set(.mpDarkTopic, isOn: true)
        fixture.model.experimental = settings
        #expect(settings.isOn(.mpDarkTopic))
        #expect(fixture.model.isEnabled(.mpFlags))
    }

    @Test func noRetiredSwitchLeavesTheOptionAsTheMemberSetIt() async throws {
        let fixture = try await Base.make(thread: 7, state: .on)
        let settings = ExperimentalSettings(store: InMemorySettingsStore())
        settings.set(.mpDarkTopic, isOn: true)
        fixture.model.experimental = settings
        #expect(settings.isOn(.mpDarkTopic))
        #expect(fixture.model.isEnabled(.mpFlags))
    }

    /// #859's list is no longer read: a stored ignore-list entry (only ever written by tests of that option) disables nothing.
    @Test func aRetiredIgnoreListEntryDisablesNothing() async throws {
        let fixture = try await Base.make(thread: 7, state: .on)
        _ = fixture.states.setFunction(.ignoreList, enabled: false, for: Base.account)
        fixture.model.reloadRecord()
        #expect(fixture.model.isEnabled(.ignoreList))
        #expect(fixture.model.writeConsent(for: .ignoreList) == .sync)
    }

    // MARK: The words

    @Test func theRefusalMessageNamesWhatIsLostAndThatNothingIsDeleted() {
        let message = MPStorageFunctionInfo.refusalMessage
        for function in MPStorageFunction.allCases { #expect(message.contains(MPStorageFunctionInfo.title(function))) }
        #expect(message.contains("Liste noire partagée") && message.contains("Favoris de messages"))
        #expect(message.contains("MP multiples → dark topic"))
        #expect(message.contains("Rien n'est supprimé"))
    }
}
