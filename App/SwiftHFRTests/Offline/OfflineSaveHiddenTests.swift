@testable import SwiftHFR
import Testing

/// #822 (decided in #903): offline save is disabled; its code stays, but no entry reaches it.
@MainActor
struct OfflineSaveHiddenTests {
    @Test func offlineSaveIsNotReachable() {
        #expect(!OfflineSaveAvailability.isReachable)
    }

    /// A topic page with a saver, the case that offered "Enregistrer cette page hors ligne" before #903: nothing now.
    @Test func theReaderOverflowOffersNoOfflineItem() {
        #expect(!ReaderOfflineSave.isOffered(hasSaver: true, isPrivate: false, hasPage: true, suspended: false))
        let entries = ReaderOverflow.entries(
            search: true,
            offline: ReaderOfflineSave.isOffered(hasSaver: true, isPrivate: false, hasPage: true, suspended: false),
            filter: true, pages: true
        )
        #expect(!entries.contains(.offline))
    }

    /// Without a saver the reader shows no progress banner and has nothing to start a save with.
    @Test func theReaderGetsNoSaver() {
        let offline = OfflineServices(
            store: EvictionSpy(), fetcher: FakeOfflineFetcher { _ throws(ListLoadError) in throw .offline },
            normalizer: LiveContentNormalizer()
        )
        #expect(ReaderOfflineSave.saver(offline) == nil)
        #expect(ReaderOfflineSave.saver(nil) == nil)
    }

    @Test func settingsHaveNoOfflineSection() {
        #expect(!SettingsView.showsOfflineSection)
    }
}
