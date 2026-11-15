import HFRNetwork
@testable import SwiftHFR
import Testing

/// #822 (decided in #903): offline save is disabled; its code stays, but no entry reaches it.
@MainActor
struct OfflineSaveHiddenTests {
    /// The single source: the screens get their offline services from the environment, which holds none, logged in or out.
    @Test(arguments: [nil, "user1"] as [String?])
    func theEnvironmentHoldsNoOfflineServices(account: String?) {
        let environment = AppEnvironment.make(session: HFRSession(), accountName: account)
        #expect(environment.reader.offline == nil)
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

    /// Réglages shows no "Hors ligne" section even for a reader that carries offline services (one built by hand, or a future
    /// environment that brings them back).
    @Test func settingsHaveNoOfflineSection() {
        var reader = AppEnvironment.make(session: HFRSession(), accountName: nil).reader
        reader.offline = OfflineServices(
            store: EvictionSpy(), fetcher: FakeOfflineFetcher { _ throws(ListLoadError) in throw .offline },
            normalizer: LiveContentNormalizer()
        )
        #expect(SettingsView.offlineEntry(in: reader) == nil)
        #expect(SettingsView.offlineEntry(in: nil) == nil)
    }
}
