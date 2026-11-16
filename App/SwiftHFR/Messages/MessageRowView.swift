import HFRModels
import SwiftUI

// Port of HFRswift/Swift/MPListView.swift (MPRowView) @ 2440d79. Differences: unread from the member's icon state
// (GAP-111); accent tint on unread rows (GAP-227); a stronger secondary colour for read titles in light (#651, GAP-227);
// "non lu" capsule for the correspondent's state (GAP-111); capsule at 4.5:1, outlined at half strength (LOT-162, #646).
/// One conversation row: avatar, subject, interlocutor(s), last message. Pure display.
struct MessageRowView: View {
    let thread: PrivateMessageThread
    /// The member's unread state as the list shows it (HFR's, until the thread is opened).
    let isUnread: Bool
    /// The row is the list's selection (iPad): the system highlight must show, so the tint steps aside.
    var isSelected = false
    /// A group row's MPStorage position, `⚑ <page> / <max>` (LOT-130); nil shows the interlocutors.
    var flagLabel: String?
    @Environment(\.listDensity) private var density
    @Environment(\.textScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// 1 at the default Dynamic Type size; multiplies the avatar and marker sizes.
    @ScaledMetric(relativeTo: .body) private var dynamicType: CGFloat = 1

    var body: some View {
        HStack(spacing: scale.scaled(dynamicType * (density == .compact ? 8 : 12))) {
            let avatar = Self.avatarSubject(of: thread)
            MessageAvatarView(pseudo: avatar.pseudo, isGroup: avatar.isGroup)
                .frame(width: avatarSide, height: avatarSide)
            VStack(alignment: .leading, spacing: density.lineSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let label = MessageRowView.unreadByLabel(thread) {
                        // The correspondent's state, not the member's: legacy's leading badge (`MPListView.swift:430-436, 470` @ 2440d79),
                        // at half strength once the member has viewed the thread (legacy line 435).
                        // Outlined instead of half-strength once the member has viewed it: the half-strength fill measured 1.7:1 (#646).
                        BadgeCapsule(text: "non lu", isOutlined: !isUnread)
                            .accessibilityLabel(label)
                    }
                    Text(thread.summary.displayTitle)
                        .scaledFont(density.titleStyle)
                        .fontWeight(titleTone.weight)
                        .foregroundStyle(titleTone.style)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : density.titleLineLimit)
                }
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

    /// The capsule's spoken label when the correspondent has not read the thread, else nil (#579).
    static func unreadByLabel(_ thread: PrivateMessageThread) -> String? {
        guard thread.isUnreadByOthers else { return nil }
        let names = thread.unreadBy.joined(separator: ", ")
        return names.isEmpty ? "Non lu par le destinataire" : "Non lu par \(names)"
    }

    /// What the avatar shows (#714): the correspondent of a one-to-one thread, never the account's own pseudo (the list's
    /// starter cell names the other member), and the group icon for a group, whether the parser read the tooltip or only
    /// HFR's "Interlocuteurs multiples" label (legacy `MPListView.swift:895-901` @ `87fe0d1c`, which tests the word "multiples";
    /// here the whole label, so a member whose pseudo holds that word keeps their avatar). A blank name has no avatar:
    /// the view then draws the monogram.
    static func avatarSubject(of thread: PrivateMessageThread) -> (pseudo: String?, isGroup: Bool) {
        let label = "Interlocuteurs multiples"
        let candidate = thread.interlocutors.first ?? thread.summary.starterOrInterlocutors
        let name = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if thread.isGroup || name.caseInsensitiveCompare(label) == .orderedSame { return (nil, true) }
        return (name.isEmpty ? nil : name, false)
    }

    /// The accent tint of an unread, unselected row; nil leaves the system background (#570).
    static func rowTint(isUnread: Bool, isSelected: Bool) -> RowTint? {
        isUnread && !isSelected ? RowTint() : nil
    }

    /// Primary and semibold when unread, secondary and regular when read (#651).
    private var titleTone: MessageTitleTone { .of(isUnread: isUnread) }

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

    /// The interlocutor of a one-to-one thread, "Interlocuteurs multiples" for a group (legacy `MPListView.swift:777`), or
    /// the group's MPStorage position instead, as legacy shows it (`MPListView.swift:775-786` @ 87fe0d1c).
    private var who: String {
        guard thread.isGroup else { return thread.summary.starterOrInterlocutors }
        if let flagLabel { return flagLabel }
        return ["Interlocuteurs multiples", counts].compactMap { $0 }.joined(separator: " · ")
    }

    /// Group rows read like topic rows (LOT-171): replies and pages, when the list row carries them.
    private var counts: String? {
        guard thread.isGroup, thread.summary.repliesCount > 0 else { return nil }
        let pages = thread.summary.pageCount
        let replies = FrenchPlural.count(thread.summary.repliesCount, "réponse", "réponses")
        return pages > 1 ? "\(replies) · \(pages) pages" : replies
    }

    private var lastPost: String? {
        guard let post = thread.summary.lastPost else { return nil }
        guard let date = post.date else { return post.author }
        return "\(post.author) · \(date.formatted(.relative(presentation: .named)))"
    }
}
