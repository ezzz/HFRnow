import Foundation
import HFRModels
import HFRStorage

// EXPERIMENTAL(mpDarkTopic, #858): adds the app's own position of a group conversation to the MPStorage flags it read only.
// Port of HFRswift/Swift/MessagesView.swift (updateMPStorageFlagIfNeeded, :3582-3606) and HFRswift/Swift/MPListView.swift
// (topicsDecoratedWithMPStorageFlags, :354-373) @ 87fe0d1c. Differences: the position is also kept in the app (LOT-090's store),
// so the option works with MP storage off; the row keeps an unread mark until the last page was reached (#858 item 3).
/// Where the account stopped in each group conversation, in the app (#858 item 2): LOT-090's reading-position store, which
/// the reader already feeds with the topmost message it shows; here a page load moves it to that page's last message, as
/// legacy moves its MPStorage flag.
struct MPReadingPositions: Sendable {
    /// The account's key (`md_user` value).
    let account: String
    /// The store read and written; the process-wide one unless a test gives its own.
    var store = LiveReaderPositionRecorder.store

    /// The account's positions in private conversations; empty while the store cannot be read.
    func positions() async -> [TopicID: ReadingPosition] {
        let records = await store.records(for: account).filter { $0.topic.category == .privateMessages }
        // Newest first: a duplicate (none is expected) keeps the newest.
        return Dictionary(records.map { ($0.topic, $0.position) }, uniquingKeysWith: { newest, _ in newest })
    }

    /// Moves the position in `topic` forward to `position`; false when it is not ahead or the store refused it (a full disk loses a
    /// position, never the reading).
    func advance(_ topic: TopicID, to position: ReadingPosition) async -> Bool {
        (try? await store.advance(topic, to: position, account: account)) ?? false
    }
}

/// What a group conversation's reader reached (#858): the page shown and its last message, the legacy flag's `page` and
/// `href` (`MessagesView.swift:3586-3606` @ 87fe0d1c, where `lastMessageAnchor` is the page's last message).
struct MPReachedMessage: Equatable, Sendable {
    /// The page shown, from 1.
    var page: Int
    /// `numreponse` of its last message.
    var lastMessage: Int

    /// What `page` shows of the conversation `source` asked for; nil before a load, for a notice or an empty page, for another
    /// conversation, and for the quote view (#1039), whose posts come from anywhere in the conversation under page 1.
    init?(page: ReaderPage?, source: ReaderTarget.Source?, of thread: PrivateMessageThread) {
        guard case .topic(let asked)? = source, let page, let topic = thread.summary.topicID, asked.topic == topic.topic,
              page.topicID.map({ $0.topic == topic.topic }) ?? true,
              let last = page.messages.last(where: { !$0.isContinuation }) else { return nil }
        self.page = max(page.currentPage, 1)
        lastMessage = last.numreponse
    }

    /// What `reader`, a reader of `thread`, shows (`init(page:source:of:)`).
    @MainActor
    init?(reader: TopicReaderModel, of thread: PrivateMessageThread) {
        self.init(page: reader.page, source: reader.shown?.source, of: thread)
    }

    /// Creates a reached message.
    init(page: Int, lastMessage: Int) {
        self.page = page
        self.lastMessage = lastMessage
    }

    /// The legacy flag of conversation `topic` at this message, `p` read from the row's link (`R13a`: `p=1`).
    func flag(topic: Int, rowLink: String?) -> MPStorageMPFlag {
        let pValue = rowLink.flatMap { URLComponents(string: $0)?.queryItems?.first { $0.name == "p" }?.value }
        return MPStorageMPFlag(conversation: topic, page: page, lastMessage: lastMessage, pValue: pValue)
    }
}

/// A group conversation's position as the list uses it (#858): the furthest of the app's own and the MPStorage flag.
struct MPConversationPosition: Equatable, Sendable {
    /// The page, from 1.
    var page: Int
    /// The message to open at (`#t<numreponse>`); nil when unknown (a flag without a usable `href`).
    var message: Int?

    /// The furthest of `local` and `flag` (legacy compares pages, `:3590`; the message breaks a tie); nil when neither is
    /// usable.
    static func furthest(local: ReadingPosition?, flag: MPStorageMPFlag?) -> MPConversationPosition? {
        let mine = local.map { MPConversationPosition(page: max($0.page, 1), message: $0.messageNumber) }
        let theirs = flag.flatMap { flag in
            flag.page.flatMap { $0 > 0 ? MPConversationPosition(page: $0, message: flag.messageNumber) : nil }
        }
        guard let mine else { return theirs }
        guard let theirs else { return mine }
        return (theirs.page, theirs.message ?? 0) > (mine.page, mine.message ?? 0) ? theirs : mine
    }
}
