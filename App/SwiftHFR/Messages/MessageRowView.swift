import HFRModels
import SwiftUI

/// One conversation row: avatar, subject, interlocutor(s), last message. Pure display.
struct MessageRowView: View {
    let thread: PrivateMessageThread
    /// The member's unread state as the list shows it (HFR's, until the thread is opened).
    let isUnread: Bool

    var body: some View {
        HStack(spacing: 12) {
            MessageAvatarView(pseudo: thread.interlocutors.first ?? thread.summary.starterOrInterlocutors, isGroup: thread.isGroup)
            VStack(alignment: .leading, spacing: 2) {
                Text(thread.summary.title)
                    .font(.body)
                    .fontWeight(isUnread ? .semibold : .regular)
                    .lineLimit(2)
                Text(who).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if let last = lastPost { Text(last).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
            if isUnread {
                Image(systemName: "circle.fill").font(.system(size: 10)).foregroundStyle(.tint).accessibilityLabel("Non lu")
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The interlocutor of a one-to-one thread, "Interlocuteurs multiples" for a group (legacy `MPListView.swift:777`).
    private var who: String {
        thread.isGroup ? "Interlocuteurs multiples" : thread.summary.starterOrInterlocutors
    }

    private var lastPost: String? {
        guard let post = thread.summary.lastPost else { return nil }
        guard let date = post.date else { return post.author }
        return "\(post.author) · \(date.formatted(.relative(presentation: .named)))"
    }
}
