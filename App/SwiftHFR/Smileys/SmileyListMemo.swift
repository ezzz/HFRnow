import HFRModels
import HFRParsing
import Foundation

/// Keeps what a smiley list loader read, for the life of the composer that owns it (#1397).
///
/// Each opening of the picker is a new `SmileyPickerModel`, so its own "already read" guards never hold across openings: three
/// openings in one composer meant three form GETs and three profile-page GETs. A success is kept; a failure (nil) is not, so the
/// section's « Réessayer » still reaches the forum.
actor SmileyListMemo<Item: Sendable> {
    private var kept: [Item]?

    /// A loader that reads through `load` once while it succeeds, and answers from memory after.
    nonisolated func memoized(_ load: @escaping @Sendable () async -> [Item]?) -> @Sendable () async -> [Item]? {
        { await self.read(load) }
    }

    private func read(_ load: @Sendable () async -> [Item]?) async -> [Item]? {
        if let kept { return kept }
        let loaded = await load()
        // Two openings racing both read; the later write is as good as the earlier.
        if let loaded { kept = loaded }
        return loaded
    }
}

/// The memos of one composer: the forum favourites and the member's own smileys.
struct SmileyListMemos: Sendable {
    let forum = SmileyListMemo<ForumSmiley>()
    let own = SmileyListMemo<OwnSmiley>()
}
