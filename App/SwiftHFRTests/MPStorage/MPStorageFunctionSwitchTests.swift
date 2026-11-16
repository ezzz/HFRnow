import Foundation
import HFRClient
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// The per-function MPStorage switches (#859), behind Réglages › Expérimental: the gate, each function's guard and the words.
@MainActor
struct MPStorageFunctionSwitchTests {
    private typealias Base = MPStorageSyncModelTests

    // MARK: One switch per function (#859)

    // MARK: Behind Réglages › Expérimental (#859)

    /// Off (the default build): legacy's single switch governs every function, whatever `disabled` holds; nothing is deleted.
    @Test func withTheOptionOffEveryFunctionIsOnWhateverTheStoredListHolds() async throws {
        let fixture = try await Base.make(thread: 7, state: .on, perFunctionSwitches: true)
        fixture.model.setFunction(.mpFlags, enabled: false)
        fixture.model.setFunction(.ignoreList, enabled: false)
        #expect(!fixture.model.isEnabled(.mpFlags))
        fixture.model.experimental?.set(.mpStorageSwitches, isOn: false)
        #expect(!fixture.model.perFunctionSwitches)
        for function in MPStorageFunction.allCases { #expect(fixture.model.isEnabled(function)) }
        #expect(fixture.model.writeConsent(for: .ignoreList) == .sync)
        #expect(fixture.states.record(for: Base.account)?.disabled == ["blacklist", "mpFlags"])
        fixture.model.experimental?.set(.mpStorageSwitches, isOn: true)
        #expect(!fixture.model.isEnabled(.mpFlags))
        #expect(fixture.model.isEnabled(.bookmarks))
    }

    @Test func withTheOptionOffTheStoredListGatesNothing() async throws {
        let text = try Base.flagged([MPStorageMPFlag(topic: 31, pValue: "1", href: "t555", page: 2)])
        let fixture = try await Base.make(
            thread: 7, state: .on, copy: MPStorageCopy(post: 7, base: text), text: text
        )
        // The list was written while the option was on (a model reads its record at creation, so through the model).
        fixture.model.setFunction(.mpFlags, enabled: false)
        fixture.model.setFunction(.ignoreList, enabled: false)
        fixture.model.experimental?.set(.mpStorageSwitches, isOn: false)
        await fixture.model.start()
        #expect(fixture.model.flag(for: messageThread(31, group: true))?.href == "t555")
        #expect(fixture.model.document(for: .ignoreList) != nil)
        let changed = await fixture.model.edit(.ignoreList) { document, stamp in
            try document.addBlocklistEntry(username: "user9", stamp: stamp)
        }
        #expect(changed)
    }

    @Test func withoutAnExperimentalEnvironmentTheOptionReadsOff() async throws {
        let fixture = try await Base.make(thread: 7, state: .on)
        fixture.model.experimental = nil
        #expect(!fixture.model.perFunctionSwitches)
        #expect(fixture.model.isEnabled(.mpFlags))
    }

    /// Legacy's section has no footer: it shows only with the option on, and never logged out.
    @Test func theFooterShowsOnlyWithTheOptionOn() async throws {
        let model = try await Base.make(thread: 7, state: .on).model
        #expect(MPStorageFunctionInfo.footer(for: model) == MPStorageFunctionInfo.footer)
        model.experimental?.set(.mpStorageSwitches, isOn: false)
        #expect(MPStorageFunctionInfo.footer(for: model) == nil)
        #expect(MPStorageFunctionInfo.footer(for: nil) == nil)
    }

    @Test func theOptionIsListedUnderMessagesAndOffByDefault() {
        #expect(ExperimentalFeature.mpStorageSwitches.isListed)
        #expect(ExperimentalTheme.messages.listedFeatures == [.mpStorageSwitches])
        #expect(!ExperimentalSettings(store: InMemorySettingsStore()).isOn(.mpStorageSwitches))
    }

    @Test func everyFunctionIsOnByDefault() async throws {
        let model = try await Base.make(thread: 7, state: .on).model
        for function in MPStorageFunction.allCases { #expect(model.isEnabled(function)) }
    }

    @Test func aFunctionOffIsStoredForThisAccountOnly() async throws {
        let fixture = try await Base.make(thread: 7, state: .on)
        fixture.states.set(.on, for: "Bob", at: Base.now)
        fixture.model.setFunction(.mpFlags, enabled: false)
        #expect(!fixture.model.isEnabled(.mpFlags))
        #expect(fixture.model.isEnabled(.bookmarks))
        #expect(fixture.states.record(for: Base.account)?.state == .on)
        #expect(fixture.states.record(for: "Bob")?.isEnabled(.mpFlags) == true)
    }

    @Test func aFunctionOffWritesNothingOfItsSection() async throws {
        let fixture = try await Base.make(
            thread: 7, state: .on, copy: MPStorageCopy(post: 7, base: FakeMPStorageRemote.emptyDocument)
        )
        fixture.model.setFunction(.ignoreList, enabled: false)
        let changed = await fixture.model.edit(.ignoreList) { document, stamp in
            try document.addBlocklistEntry(username: "user9", stamp: stamp)
        }
        #expect(!changed)
        #expect(await fixture.remote.calls.isEmpty)
        #expect(fixture.model.writeConsent(for: .ignoreList) == .deviceOnly)
        #expect(fixture.model.writeConsent(for: .bookmarks) == .sync)
    }

    @Test func aResyncWithAFunctionOffLeavesItsSectionInTheDocument() async throws {
        var document = try MPStorageCodec.decode(FakeMPStorageRemote.emptyDocument)
        _ = try document.addBlocklistEntry(username: "user9", stamp: MPStorageStamp(date: Base.now))
        let text = try MPStorageCodec.encodeForWriting(document)
        let fixture = try await Base.make(thread: 7, state: .on, copy: MPStorageCopy(post: 7, base: text), text: text)
        await fixture.model.start()
        #expect(fixture.model.document(for: .ignoreList)?.data.first?.blocklist?.list.map(\.username) == ["user9"])
        fixture.model.setFunction(.ignoreList, enabled: false)
        await fixture.model.resync()
        #expect(fixture.model.document(for: .ignoreList) == nil)
        #expect(fixture.model.document(for: .bookmarks) != nil)
        #expect(fixture.model.document?.data.first?.blocklist?.list.map(\.username) == ["user9"])
        #expect(await !fixture.remote.calls.contains(.save))
    }

    @Test func switchingTheMainSwitchOffAndOnKeepsTheFunctionSwitches() async throws {
        let fixture = try await Base.make(thread: 7, state: .on)
        fixture.model.setFunction(.mpFlags, enabled: false)
        await fixture.model.setEnabled(false)
        await fixture.model.setEnabled(true)
        #expect(fixture.model.isEnabled(.bookmarks))
        #expect(!fixture.model.isEnabled(.mpFlags))
    }

    @Test(arguments: MPStorageFunction.allCases)
    func everyFunctionHasATitleAnExplanationAndAnInfoLabel(_ function: MPStorageFunction) {
        #expect(!MPStorageFunctionInfo.title(function).isEmpty)
        #expect(MPStorageFunctionInfo.explanation(function).contains("rien n'y est supprimé"))
        #expect(MPStorageFunctionInfo.infoLabel(function) == "Plus d'infos sur \(MPStorageFunctionInfo.title(function))")
    }

    @Test func everyShownFunctionIsRealAndGatesItsSection() async throws {
        let shown = MPStorageSyncModel.shippedFunctions
        #expect(!shown.isEmpty)
        #expect(!shown.contains(.ignoreList) && !shown.contains(.bookmarks)) // their lots (#221, #222) have not shipped
        for function in shown {
            let fixture = try await Base.make(thread: 7, state: .on, copy: MPStorageCopy(post: 7, base: FakeMPStorageRemote.emptyDocument))
            await fixture.model.start()
            #expect(fixture.model.document(for: function) != nil)
            fixture.model.setFunction(function, enabled: false)
            #expect(fixture.model.document(for: function) == nil)
        }
    }

    @Test func anEditQueuedBeforeTheSwitchOffIsStillWrittenAtTheNextSync() async throws {
        let fixture = try await Base.make(
            thread: 7, state: .on, copy: MPStorageCopy(post: 7, base: FakeMPStorageRemote.emptyDocument)
        )
        await fixture.remote.fail(with: .network(.offline))
        _ = await fixture.model.edit(.ignoreList) { document, stamp in
            try document.addBlocklistEntry(username: "user9", stamp: stamp)
        }
        #expect(await fixture.copies.copy(for: Base.account)?.pending != nil)
        fixture.model.setFunction(.ignoreList, enabled: false)
        await fixture.remote.fail(with: nil)
        await fixture.model.resync()
        #expect(await fixture.remote.calls.contains(.save))
        #expect(await fixture.copies.copy(for: Base.account)?.pending == nil)
    }
}
