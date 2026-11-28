import HFRModels
import HFRStorage
import Observation

// EXPERIMENTAL(mpDarkTopic, #858): replaces the group rows' read-only MPStorage flag (`flagLabel`, the opening at the latest
// message) by the conversation's position, the app's own or the flag, whichever is further.
// Port of HFRswift/Swift/MPListView.swift (topicsDecoratedWithMPStorageFlags, :354-373; interlocutorLabel, :775-786),
// HFRswift/Swift/Common.swift (TopicOpenPolicy `.privateMessages`, :2738-2742) and HFRswift/Swift/MessagesView.swift
// (updateMPStorageFlagIfNeeded, :3582-3606) @ 87fe0d1c. Differences: the app keeps its own position (MP storage off too) and
// a row stays marked unread until its last page was reached (#858 items 2 and 3); the flag is sent once per visit.
extension MessageListModel {
    /// Whether « MP multiples → dark topic » is on for the account (Réglages › Expérimental); off logged out.
    var darkTopicIsOn: Bool { MPDarkTopic.isOn(for: mpStorage) }

    /// Where the member stopped in `thread`: the furthest of the app's position and the MPStorage flag; nil for a one-to-one
    /// conversation, with the option off, or when neither is known.
    func position(for thread: PrivateMessageThread) -> MPConversationPosition? {
        guard darkTopicIsOn, thread.isGroup, let topic = thread.summary.topicID else { return nil }
        return MPConversationPosition.furthest(local: darkTopic.positions[topic], flag: mpStorage?.flag(for: thread))
    }

    /// The group row's position as legacy wrote its flag, `⚑ <page> / <max>` (`MPListView.swift:775-786` @ 87fe0d1c), max being
    /// at least the position's page (`:368`); nil without one (one-to-one rows, the dark-topic option off, nothing read yet).
    func flagLabel(for thread: PrivateMessageThread) -> String? {
        guard let page = position(for: thread)?.page else { return nil }
        let current = max(page, 1)
        return "⚑ \(current) / \(max(thread.summary.pageCount, current))"
    }

    /// Whether `thread` was left before its last page (#858 item 3): an app-side unread mark, whatever HFR's icon says. A
    /// new message on a new page brings it back; one on the page reached makes HFR's own state unread.
    func isNotFullyRead(_ thread: PrivateMessageThread) -> Bool {
        guard let position = position(for: thread) else { return false }
        return position.page < thread.summary.pageCount
    }

    /// Whether the row shows unread: HFR's state as the list knows it (`isUnread`), or left before its last page. Display only:
    /// the badge and the segment counts stay HFR's.
    func showsUnread(_ thread: PrivateMessageThread) -> Bool {
        isUnread(thread) || isNotFullyRead(thread)
    }

    /// The reader of `thread` shows `reached` (a page load): the app's position moves forward to that page's last message, and
    /// the MPStorage flag with it in the device copy (sent when the conversation is left). Nothing for a one-to-one
    /// conversation or with the option off.
    func reached(_ reached: MPReachedMessage, in thread: PrivateMessageThread) async {
        guard darkTopicIsOn, thread.isGroup, let topic = thread.summary.topicID else { return }
        let position = ReadingPosition(page: reached.page, messageNumber: reached.lastMessage)
        if darkTopic.positions[topic].map({ position.isAhead(of: $0) }) ?? true {
            darkTopic.positions[topic] = position
        }
        _ = await darkTopic.store?.advance(topic, to: position)
        await mpStorage?.moveFlag(of: thread, to: reached)
    }

    /// Reads the app's positions again (after a list load: another window or device may have moved them).
    func reloadPositions() async {
        guard darkTopicIsOn, let readingPositions = darkTopic.store else { return }
        let stored = await readingPositions.positions()
        // A position reached while the read ran is ahead of what it read: keep the further one.
        darkTopic.positions = stored.merging(darkTopic.positions) { read, local in local.isAhead(of: read) ? local : read }
    }

    /// The conversation `previous` was left for `current`: the flags moved while reading it are sent, in one write.
    func conversationChanged(from previous: PrivateMessageThread?, to current: PrivateMessageThread?) {
        guard let previous, previous.id != current?.id, let mpStorage else { return }
        darkTopic.flagSend = Task { await mpStorage.sendMovedFlags() }
    }

    /// The opening of a row that has a position: its page, at its message (legacy opens at the flag's link whenever there is one).
    func positionOpening(of thread: PrivateMessageThread) -> (target: ReaderTarget, fromLatestMessage: Bool)? {
        guard let position = position(for: thread), let topic = thread.summary.topicID else { return nil }
        return (ReaderTarget(source: .topic(topic), page: position.page, anchor: position.message), false)
    }
}

// EXPERIMENTAL(mpDarkTopic, #858): the list's state for the option, in one place.
/// The app's positions of the group conversations as the list shows them, and the send of the flags moved in the conversation
/// just left.
@MainActor
@Observable
final class MPDarkTopicPositions {
    /// Where the account's positions are kept; nil logged out.
    let store: MPReadingPositions?
    /// The positions last read from `store`, moved forward by `MessageListModel.reached(_:in:)`.
    var positions: [TopicID: ReadingPosition] = [:]
    /// The send of the flags moved in the conversation just left (tests await it).
    @ObservationIgnored var flagSend: Task<Void, Never>?

    /// The state over `store`, empty until the list loads.
    init(store: MPReadingPositions?) {
        self.store = store
    }
}
