import Foundation
import HFRModels
import HFRStorage

/// What the offline screens need from the saved pages (LOT-068's `OfflineTopicStore`), always off the main actor: a save
/// decodes the whole page's character references (about 100 ms a page in a debug build) and the list reads one file per topic.
protocol OfflineStoring: Sendable {
    /// Saves `page`, replacing the same page.
    func save(_ page: OfflinePage) async throws(OfflineStoreError)
    /// The saved topics, most recent first.
    func topics() async throws(OfflineStoreError) -> [OfflineTopic]
    /// One saved page; nil when it was never saved or has been evicted.
    func page(_ number: Int, of topic: TopicID) async throws(OfflineStoreError) -> OfflinePage?
    /// Removes every page of `topic`.
    func remove(_ topic: TopicID) async throws(OfflineStoreError)
    /// Removes every saved page.
    func removeAll() async throws(OfflineStoreError)
    /// Bytes the saved pages take on disk.
    func sizeOnDisk() async -> Int
}

/// The device's store. `nonisolated` async functions of a `Sendable` struct run off the main actor, which is the point.
struct LiveOfflineStore: OfflineStoring {
    let store: OfflineTopicStore
    /// Called when a store call starts, on the thread that runs it (tests check it is not the main one).
    let onStart: @Sendable () -> Void

    init(store: OfflineTopicStore = OfflineTopicStore(), onStart: @escaping @Sendable () -> Void = {}) {
        self.store = store
        self.onStart = onStart
    }

    @concurrent func save(_ page: OfflinePage) async throws(OfflineStoreError) {
        onStart()
        try store.save(page)
    }
    @concurrent func topics() async throws(OfflineStoreError) -> [OfflineTopic] {
        onStart()
        return try store.topics()
    }
    @concurrent func page(_ number: Int, of topic: TopicID) async throws(OfflineStoreError) -> OfflinePage? {
        onStart()
        return try store.page(number, of: topic)
    }
    @concurrent func remove(_ topic: TopicID) async throws(OfflineStoreError) {
        onStart()
        try store.remove(topic)
    }
    @concurrent func removeAll() async throws(OfflineStoreError) {
        onStart()
        try store.removeAll()
    }
    @concurrent func sizeOnDisk() async -> Int {
        onStart()
        return store.cache.size(of: .offlineTopics)
    }
}

extension OfflineStoreError {
    /// What the screen tells the member. A page that holds session data is named as such, not failed silently (LOT-068 review).
    var message: String {
        switch self {
        case .containsSessionToken: "Page non enregistrable : elle contient des données de session."
        case .beyondPageLimit:
            "Ce sujet a déjà \(OfflineTopicStore.defaultMaximumPagesPerTopic) pages enregistrées, toutes après celle-ci."
        case .invalidTopic: "Seuls les sujets du forum peuvent être enregistrés."
        case .emptyPage: "La page est vide."
        case .unsupportedVersion, .unreadable:
            "Cette page enregistrée est illisible : supprimez-la puis enregistrez-la de nouveau."
        case .unsafeFolder, .fileFailed:
            "L’enregistrement a échoué : le stockage de l’appareil est inaccessible."
        }
    }
}
