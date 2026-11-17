import HFRModels
import SwiftUI

// DenseTopicRowView: port of HFRswift/Swift/Favorites.swift (TopicRowView) @ 2440d79. Differences: legacy "last-post author - date" becomes
// "⚑ cur / max · last poster · age" on one line (no reply count, no starter, no « il y a », #905 C-E; `DenseRowFormat`); the
// unread-pages capsule (kept with the dot for unread rows); the flag colour tints the icon and the row (GAP-026, 027, #584).
// Title: `TopicSummary.displayTitle` ports `filterTU` (`Topic.m:90-94` @ 87fe0d1c; #818). The row shows no other rewrite.
// Density and text size: legacy TopicListRowView (Common.swift:3194-3245 @ 21173e77) and FavoritesListDensity (LOT-169).
/// EXPERIMENTAL(denseRows, #905): the dense topic row: dot and flag icon before the title, then one info line (« ⚑ lue / total ·
/// last poster · age », `DenseRowFormat`). Pure display.
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
            // EXPERIMENTAL(denseRows, #905): the unread dot and the flag icon before the title, in place of the legacy rows of
            // #817 (`LegacyTopicRowView`, the default), read at `TopicRowStyle.current`.
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
                    if let info = DenseRowFormat.topicInfo(topic, showsFlag: showsFlag) {
                        Text(info).denseInfoLine(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
                    }
                }
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
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
}
