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

    init(services: OfflineServices) {
        self.services = services
    }

    /// Reads the saved topics and their size (off the main actor: one file is decoded per topic).
    func load() async {
        do throws(OfflineStoreError) {
            let found = try await services.store.topics()
            topics = Self.displayOrder(found)
            errorMessage = nil
        } catch {
            errorMessage = error.message
        }
        sizeOnDisk = await services.store.sizeOnDisk()
        hasLoaded = true
    }

    /// Deletes every saved page of `topic`.
    func remove(_ topic: OfflineTopic) async {
        do throws(OfflineStoreError) {
            try await services.store.remove(topic.topic)
        } catch {
            errorMessage = error.message
        }
        await load()
    }

    /// Deletes every saved page.
    func removeAll() async {
        do throws(OfflineStoreError) {
            try await services.store.removeAll()
        } catch {
            errorMessage = error.message
        }
        await load()
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
