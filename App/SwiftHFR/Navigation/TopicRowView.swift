import HFRModels
import SwiftUI

// DenseTopicRowView: port of HFRswift/Swift/Favorites.swift (TopicRowView) @ 2440d79. Differences: legacy "last-post author - date" becomes
// "starter or interlocutors · replies · relative date of the last post" (replies added, starter instead of the last poster), after the
// "⚑ cur / max" footer; the unread-pages capsule (kept with the dot for unread rows); the flag colour tints the icon and the row
// (GAP-026, 027, #584; `TopicRowCues`).
// Title: `TopicSummary.displayTitle` ports `filterTU` (`Topic.m:90-94` @ 87fe0d1c; #818). The row shows no other rewrite.
// Density and text size: legacy TopicListRowView (Common.swift:3194-3245 @ 21173e77) and FavoritesListDensity (LOT-169).
/// Which row the lists draw.
enum TopicRowStyle {
    /// Legacy's row (default): pin and lock before the title, unread-pages pill, "⚑ lue / total" and "dernier posteur - date".
    case legacy
    /// Today's dense row, kept for Réglages › Expérimental › « Lignes avec icônes de drapeau » (#905).
    case dense

    /// EXPERIMENTAL(flagIconRows, #905): the switch point; #905 reads the option here. Until then the default is legacy's row.
    static var current: TopicRowStyle { .legacy }
}

/// One topic row, in the current style. Pure display.
struct TopicRowView: View {
    let topic: TopicSummary
    var isSuperFavorite = false
    var markedRead = false
    var showsFlag = true

    var body: some View {
        switch TopicRowStyle.current {
        case .legacy:
            LegacyTopicRowView(topic: topic, isSuperFavorite: isSuperFavorite, markedRead: markedRead, showsFlag: showsFlag)
        case .dense: DenseTopicRowView(topic: topic, isSuperFavorite: isSuperFavorite, markedRead: markedRead, showsFlag: showsFlag)
        }
    }
}

/// EXPERIMENTAL(flagIconRows, #905): today's row, unchanged: title, flag, counters and last post. Pure display.
struct DenseTopicRowView: View {
    let topic: TopicSummary
    /// A super-favourite of the account (LOT-124): the row carries an orange mark.
    var isSuperFavorite = false
    /// The user marked the row "Lu" since the last load (LOT-125): it shows as read.
    var markedRead = false
    /// The row shows its flag (LOT-125: false once HFR confirmed the flag removed).
    var showsFlag = true
    @Environment(\.listDensity) private var density
    @Environment(\.textScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// 1 at the default Dynamic Type size; multiplies the spacing between the marks and the title.
    @ScaledMetric(relativeTo: .body) private var dynamicType: CGFloat = 1

    private var isUnread: Bool { topic.readState == .unread && !markedRead }

    var body: some View {
        HStack(alignment: .top, spacing: scale.scaled(dynamicType * 8)) {
            // EXPERIMENTAL(flagIconRows, #905): the unread dot and the flag icon before the title, in place of the legacy rows of
            // #817 (`LegacyTopicRowView`, the default). #905 reads the option at `TopicRowStyle.current`.
            if isUnread { UnreadDotMark() }
            if isSuperFavorite {
                Image(systemName: "star.circle.fill").foregroundStyle(.orange)
                    .scaledFont(density.titleStyle).accessibilityLabel("Super favori")
            }
            if showsFlag { FlagIconMark(flag: topic.flag).scaledFont(density.titleStyle) }
            VStack(alignment: .leading, spacing: density.lineSpacing) {
                Text(topic.displayTitle)
                    .scaledFont(density.titleStyle)
                    .fontWeight(isUnread ? .semibold : .regular)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : density.titleLineLimit)
                HStack(spacing: 6) {
                    if topic.isSticky { Image(systemName: "pin.fill").accessibilityLabel("Post-it") }
                    if topic.isClosed { Image(systemName: "lock.fill").accessibilityLabel("Fermé") }
                    if topic.isPoll { Image(systemName: "chart.bar.fill").accessibilityLabel("Sondage") }
                    Text(summary)
                }
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(density == .compact && !dynamicTypeSize.isAccessibilitySize ? 1 : nil)
            }
            if let pages = TopicRowCues.unreadPages(topic), showsFlag {
                Spacer(minLength: 0)
                BadgeCapsule(text: "\(pages)", isBold: true)
                    .accessibilityLabel(TopicRowCues.unreadPagesLabel(pages))
            }
        }
        .accessibilityElement(children: .combine)
        .listRowInsets(density.rowInsets)
    }

    private var summary: String {
        var parts: [String] = []
        if showsFlag, let footer = TopicRowCues.pageFooter(topic) { parts.append(footer) }
        if !topic.starterOrInterlocutors.isEmpty { parts.append(topic.starterOrInterlocutors) }
        parts.append(FrenchPlural.count(topic.repliesCount, "réponse", "réponses"))
        if let date = topic.lastPost?.date { parts.append(date.formatted(.relative(presentation: .named))) }
        return parts.joined(separator: " · ")
    }
}
