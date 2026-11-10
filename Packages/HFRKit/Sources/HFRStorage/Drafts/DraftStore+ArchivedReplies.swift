import Foundation
import HFRModels

/// Archived replies (LOT-101): up to three per topic and account, newest first, kept in the same file and under the same
/// time-to-live as every other draft. Legacy kept them in `UserDefaults` for every account at once
/// (`reply_drafts_by_topic_v1`, `AnswerView.swift:137-244` @ 87fe0d1c).
extension DraftStore {
    /// How many replies are kept per topic: the oldest are dropped.
    public static let maximumArchivedRepliesPerTopic = 3

    /// The archived replies of a topic for an account, newest first.
    public func archivedReplies(topic: TopicID, account: String) -> [ArchivedDraft] {
        let key = AccountKey.make(account)
        let entries: [ArchivedDraft] = liveDrafts(now: clock()).compactMap { draft in
            guard draft.account == key, case .archivedReply(let owner, let id, let source) = draft.context, owner == topic else {
                return nil
            }
            return ArchivedDraft(id: id, text: draft.text, source: source, archivedAt: draft.updatedAt)
        }
        return Self.newestFirst(entries, by: \.archivedAt)
    }

    /// Sets `text` aside for a topic, as the newest. Blank text is never archived (nil, nothing written); the same text
    /// again (ignoring surrounding whitespace) replaces the earlier copy, so a topic holds each text once. Past
    /// `maximumArchivedRepliesPerTopic` the oldest go.
    @discardableResult
    public func archiveReply(_ text: String, topic: TopicID, source: ArchivedDraftSource, account: String) throws -> ArchivedDraft? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let now = clock()
        let key = AccountKey.make(account)
        let id = UUID()
        try mutate { drafts in
            drafts.removeAll { draft in
                guard draft.account == key, case .archivedReply(let owner, _, _) = draft.context, owner == topic else { return false }
                return draft.text.trimmingCharacters(in: .whitespacesAndNewlines) == normalized
            }
            drafts.append(Draft(context: .archivedReply(topic: topic, id: id, source: source), account: key, text: text, updatedAt: now))
            self.dropOldestArchivedReplies(of: topic, account: key, from: &drafts)
            self.applyBounds(&drafts, now: now)
            return true
        }
        return ArchivedDraft(id: id, text: text, source: source, archivedAt: now)
    }

    /// Removes one archived reply. Returns false when it was not there.
    @discardableResult
    public func discardArchivedReply(id: UUID, topic: TopicID, account: String) throws -> Bool {
        let key = AccountKey.make(account)
        return try mutate { drafts in
            let before = drafts.count
            drafts.removeAll { draft in
                guard draft.account == key, case .archivedReply(let owner, let other, _) = draft.context else { return false }
                return owner == topic && other == id
            }
            return drafts.count != before
        }
    }

    /// Removes every archived reply of a topic ("Vider"). Returns how many were removed.
    @discardableResult
    public func discardArchivedReplies(topic: TopicID, account: String) throws -> Int {
        let key = AccountKey.make(account)
        var removed = 0
        try mutate { drafts in
            let before = drafts.count
            drafts.removeAll { draft in
                guard draft.account == key, case .archivedReply(let owner, _, _) = draft.context else { return false }
                return owner == topic
            }
            removed = before - drafts.count
            return removed > 0
        }
        return removed
    }

    private func dropOldestArchivedReplies(of topic: TopicID, account: String, from drafts: inout [Draft]) {
        let mine = drafts.enumerated().filter { _, draft in
            guard draft.account == account, case .archivedReply(let owner, _, _) = draft.context else { return false }
            return owner == topic
        }
        guard mine.count > Self.maximumArchivedRepliesPerTopic else { return }
        // Newest first; on equal dates the one appended later is the newer.
        let ordered = mine.sorted { ($0.element.updatedAt, $0.offset) > ($1.element.updatedAt, $1.offset) }
        let doomed = Set(ordered.dropFirst(Self.maximumArchivedRepliesPerTopic).map(\.offset))
        drafts = drafts.enumerated().filter { !doomed.contains($0.offset) }.map(\.element)
    }

    private static func newestFirst<T>(_ items: [T], by date: KeyPath<T, Date>) -> [T] {
        items.enumerated().sorted { (items[$0.offset][keyPath: date], $0.offset) > (items[$1.offset][keyPath: date], $1.offset) }.map(\.element)
    }
}
