import Foundation
import HFRModels
import HFRStorage
import Observation

/// The list of saved topics (LOT-139): load, delete one, delete all, size on disk.
@MainActor
@Observable
final class OfflineTopicsModel {
    /// The saved topics, in `display order`.
    private(set) var topics: [OfflineTopic] = []
    /// Bytes the saved pages take.
    private(set) var sizeOnDisk = 0
    /// The list was read at least once.
    private(set) var hasLoaded = false
    /// What the member is told when a read or a deletion failed; cleared by the next success.
    private(set) var errorMessage: String?

    let services: OfflineServices
    private var generation = 0

    init(services: OfflineServices) {
        self.services = services
    }

    /// Reads the saved topics and their size (off the main actor: one file is decoded per topic).
    func load() async {
        generation += 1
        let mine = generation
        var found: [OfflineTopic]?
        var failure: String?
        do throws(OfflineStoreError) {
            found = try await services.store.topics()
        } catch {
            failure = error.message
        }
        let size = await services.store.sizeOnDisk()
        // An older read that finishes after a newer one must not put its list back.
        guard mine == generation else { return }
        if let found {
            topics = Self.displayOrder(found)
            errorMessage = nil
        } else {
            errorMessage = failure
        }
        sizeOnDisk = size
        hasLoaded = true
    }

    /// Deletes every saved page of `topic`.
    func remove(_ topic: OfflineTopic) async {
        var failure: String?
        do throws(OfflineStoreError) {
            try await services.store.remove(topic.topic)
        } catch {
            failure = error.message
        }
        await load()
        // The reload's own success must not wipe the reason the deletion failed.
        if let failure { errorMessage = failure }
    }

    /// Deletes every saved page.
    func removeAll() async {
        var failure: String?
        do throws(OfflineStoreError) {
            try await services.store.removeAll()
        } catch {
            failure = error.message
        }
        await load()
        if let failure { errorMessage = failure }
    }

    /// The reader of `topic`, opened on its first saved page.
    func reader(for topic: OfflineTopic, renderOptions: @escaping @Sendable () -> ReaderRenderOptions) -> TopicReaderModel {
        TopicReaderModel(
            target: ReaderTarget(source: .topic(topic.topic), page: topic.pages.first ?? 1),
            title: topic.title, source: services.pageSource, renderOptions: renderOptions
        )
    }

    private static func forum(_ topic: OfflineTopic) -> Int {
        if case .forum(let number) = topic.topic.category { return number }
        return Int.max
    }

    /// Most recently saved first; two topics saved at the same instant are ordered by forum, then topic number (LOT-068's own
    /// tie-break ignores the forum, so equal dates could swap places between two reads).
    static func displayOrder(_ topics: [OfflineTopic]) -> [OfflineTopic] {
        topics.sorted { left, right in
            if left.lastSavedAt != right.lastSavedAt { return left.lastSavedAt > right.lastSavedAt }
            if Self.forum(left) != Self.forum(right) { return Self.forum(left) < Self.forum(right) }
            return left.topic.topic < right.topic.topic
        }
    }
}
