import HFRModels
import SwiftUI

// Port of HFRswift/Swift/MPListView.swift (MPRowView) @ 2440d79. Differences: unread from the member's icon state (GAP-111).
/// One conversation row: avatar, subject, interlocutor(s), last message. Pure display.
struct MessageRowView: View {
    let thread: PrivateMessageThread
    /// The member's unread state as the list shows it (HFR's, until the thread is opened).
    let isUnread: Bool
    @Environment(\.listDensity) private var density
    @Environment(\.textScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// 1 at the default Dynamic Type size; multiplies the avatar and marker sizes.
    @ScaledMetric(relativeTo: .body) private var dynamicType: CGFloat = 1

    var body: some View {
        HStack(spacing: scale.scaled(dynamicType * (density == .compact ? 8 : 12))) {
            MessageAvatarView(pseudo: thread.interlocutors.first ?? thread.summary.starterOrInterlocutors, isGroup: thread.isGroup)
                .frame(width: avatarSide, height: avatarSide)
            VStack(alignment: .leading, spacing: density.lineSpacing) {
                Text(thread.summary.title)
                    .scaledFont(density.titleStyle)
                    .fontWeight(isUnread ? .semibold : .regular)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : density.titleLineLimit)
                if density.mergesMetaLines {
                    Text(MessageRowView.metaLine(who: who, lastPost: lastPost))
                        .scaledFont(.caption).foregroundStyle(.secondary).lineLimit(metaLineLimit)
                } else {
                    Text(who).scaledFont(.subheadline).foregroundStyle(.secondary).lineLimit(metaLineLimit)
                    if let last = lastPost { Text(last).scaledFont(.caption).foregroundStyle(.secondary).lineLimit(metaLineLimit) }
                }
            }
            Spacer(minLength: 0)
            if isUnread {
                let marker = scale.scaled(dynamicType * (density.markerSize + 2))
                Circle().fill(.tint).frame(width: marker, height: marker).accessibilityLabel("Non lu")
            }
        }
        .accessibilityElement(children: .combine)
        .listRowInsets(density.rowInsets)
    }

    /// Capped, so an accessibility size leaves the text its room.
    private var avatarSide: CGFloat { min(scale.scaled(dynamicType * density.avatarSize), 64) }

    /// One line per meta line, except at accessibility sizes, where nothing truncates.
    private var metaLineLimit: Int? { dynamicTypeSize.isAccessibilitySize ? nil : 1 }

    /// The compact row's single meta line: who, then the last post when there is one; a last post by `who` names them once.
    static func metaLine(who: String, lastPost: String?) -> String {
        guard let lastPost, !lastPost.isEmpty else { return who }
        if lastPost == who || lastPost.hasPrefix("\(who) · ") { return lastPost }
        return "\(who) · \(lastPost)"
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
