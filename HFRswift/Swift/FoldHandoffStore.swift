import Observation
import SwiftUI

/// Carries the topic being read across a root swap (iPhone Duo fold/unfold, iPad Split View
/// resize): `RootTabView` shows a `TabView` with push navigation in compact size classes and a
/// `NavigationSplitView` driven by `TopicNavigationTarget`s in regular/regular. The two
/// hierarchies share no navigation state, so the root `MessagesView` of each tab registers what
/// it shows here, and `RootTabView` replays it into the other hierarchy when the root changes.
@Observable
@MainActor
final class FoldHandoffStore {
    static let shared = FoldHandoffStore()

    /// What the root `MessagesView` of the selected tab currently shows.
    struct Reading {
        let token: UUID
        let tab: RootTabIdentifier
        let topic: Topic
        var page: Int
        var maxPage: Int
    }

    /// A topic to push on a compact tab root after a fold.
    struct PendingPush: Identifiable {
        let id = UUID()
        let tab: RootTabIdentifier
        let target: TopicNavigationTarget
    }

    private(set) var reading: Reading?
    private(set) var pendingPush: PendingPush?
    /// Bumped on every root swap. A `MessagesView` torn down by the swap must not clear the
    /// reading the swap is about to replay.
    @ObservationIgnored private(set) var rootGeneration = 0

    private init() {}

    #if DEBUG
    /// Unit tests only: the store is a process-wide singleton.
    func resetForTesting() {
        reading = nil
        pendingPush = nil
        rootGeneration = 0
    }
    #endif

    func register(tab: RootTabIdentifier, topic: Topic, page: Int, maxPage: Int) -> UUID {
        let token = UUID()
        reading = Reading(token: token, tab: tab, topic: topic, page: page, maxPage: maxPage)
        return token
    }

    func update(token: UUID, page: Int, maxPage: Int) {
        guard reading?.token == token else { return }
        reading?.page = page
        reading?.maxPage = max(maxPage, page)
    }

    /// Called when a root `MessagesView` disappears. The clear is deferred so that a root swap
    /// happening in the same update (fold/unfold) wins over the teardown of the old hierarchy.
    @discardableResult
    func scheduleClear(token: UUID, after delay: Duration = .milliseconds(400)) -> Task<Void, Never> {
        let generation = rootGeneration
        return Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard self.rootGeneration == generation, self.reading?.token == token else { return }
            self.reading = nil
        }
    }

    /// Records a root swap and returns the reading to replay, if it belongs to `tab`.
    func beginRootSwap(selectedTab tab: RootTabIdentifier) -> Reading? {
        rootGeneration += 1
        pendingPush = nil
        guard let reading, reading.tab == tab else { return nil }
        return reading
    }

    func requestCompactPush(tab: RootTabIdentifier, target: TopicNavigationTarget) {
        pendingPush = PendingPush(tab: tab, target: target)
    }

    func consumePendingPush(for tab: RootTabIdentifier) -> TopicNavigationTarget? {
        guard let pendingPush, pendingPush.tab == tab else { return nil }
        self.pendingPush = nil
        return pendingPush.target
    }
}

extension FoldHandoffStore.Reading {
    /// Rebuilds a navigation target on the page being read. The open context only feeds the
    /// split view's selection highlight (`TopicNavigationIdentity`).
    var navigationTarget: TopicNavigationTarget {
        TopicNavigationTarget(
            topic: topic,
            page: page,
            maxPage: max(maxPage, page),
            openedURL: nil,
            initialScroll: nil,
            context: tab.foldHandoffOpenContext,
            separatorNewMessages: false
        )
    }
}

private extension RootTabIdentifier {
    var foldHandoffOpenContext: TopicOpenContext {
        switch self {
        case .favorites:
            .favorites
        case .messages:
            .privateMessages
        case .categories, .more:
            .generic
        }
    }
}
