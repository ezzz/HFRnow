// Port of HFRswift/Swift/Common.swift (MessagesNotificationNavigation) @ 87fe0d1c. Differences: a conversation's number next
// to the legacy `destination = messages`, so a tap opens it (GAP-011; operator decision of 2026-11-07 on #230).
/// Where a tap on an MP notification leads: a conversation, or the list.
enum MPNotificationDestination: Sendable, Equatable {
    /// The MP list (a summary, or the legacy text).
    case list
    /// The conversation with this topic number.
    case thread(Int)

    /// Legacy key and value (`Common.swift:58-59`), so the notifications of both apps read alike.
    static let destinationKey = "destination"
    static let messagesValue = "messages"
    /// The conversation's topic number.
    static let topicKey = "mpTopic"

    /// The destination of a conversation's notification, or the list's.
    init(topic: Int?) {
        self = topic.map(Self.thread) ?? .list
    }

    /// Reads a notification's `userInfo`; nil for a notification that is not an MP one. Legacy also opened the list for a
    /// notification without a destination (`HFRplusAppDelegate.m:192-193`); SwiftHFR posts no other kind.
    init?(userInfo: [AnyHashable: Any]) {
        let destination = userInfo[Self.destinationKey] as? String
        guard destination == nil || destination == Self.messagesValue else { return nil }
        if let topic = userInfo[Self.topicKey] as? Int, topic > 0 {
            self = .thread(topic)
        } else {
            self = .list
        }
    }

    /// What the notification carries.
    var userInfo: [AnyHashable: Any] {
        switch self {
        case .list: [Self.destinationKey: Self.messagesValue]
        case .thread(let topic): [Self.destinationKey: Self.messagesValue, Self.topicKey: topic]
        }
    }
}
