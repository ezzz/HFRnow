import Foundation
import HFRClient
import HFRModels
import HFRNetwork
@testable import SwiftHFR

/// A scripted flag writer: records each write and answers what its handlers say; nothing reaches HFR.
final class FakeFlagWriter: TopicFlagWriting, @unchecked Sendable {
    typealias RemoveHandler = @Sendable (TopicID) async throws(TopicFlagError) -> TopicFlagResult
    typealias AddHandler = @Sendable (URL) async throws(TopicFlagError) -> TopicFlagResult

    private let lock = NSLock()
    private var removals: [TopicID] = []
    private var additions: [URL] = []
    var removeHandler: RemoveHandler = { topic in confirmed(.removeFavoriteFromList, topic, "Drapeaux effacés avec succès") }
    var addHandler: AddHandler = { _ in
        confirmed(.addFavorite, TopicID(category: .forum(13), topic: 1), "Favori positionné avec succès")
    }

    /// Topics whose removal was sent, in order.
    var removed: [TopicID] { lock.withLock { removals } }
    /// Links followed to add a favourite, in order.
    var added: [URL] { lock.withLock { additions } }

    func removeFavorite(_ topic: TopicID) async throws(TopicFlagError) -> TopicFlagResult {
        lock.withLock { removals.append(topic) }
        return try await removeHandler(topic)
    }

    func addFavorite(link: URL) async throws(TopicFlagError) -> TopicFlagResult {
        lock.withLock { additions.append(link) }
        return try await addHandler(link)
    }
}

/// HFR's confirmation of `action` on `topic`.
func confirmed(_ action: TopicFlagAction, _ topic: TopicID, _ message: String) -> TopicFlagResult {
    TopicFlagResult(action: action, topic: topic, message: message, refreshURL: URL(string: "https://forum.hardware.fr/")!)
}

/// A flagged favourites row of category 13 (`flag: .blue`), on `pages` pages.
func flaggedTopic(_ number: Int, pages: Int = 1, flag: TopicFlag? = .blue, read: TopicReadState = .unread) -> TopicSummary {
    TopicSummary(
        topicID: TopicID(category: .forum(13), topic: number), title: "Sujet \(number)", path: "/t13-\(number)",
        pageCount: pages, flag: flag, readState: read
    )
}
