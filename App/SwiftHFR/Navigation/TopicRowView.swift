import HFRModels
import SwiftUI

// Port of HFRswift/Swift/Favorites.swift (TopicRowView) @ 2440d79. Differences: legacy "last-post author - date" becomes
// "starter or interlocutors · replies · relative date of the last post" (replies added, starter instead of the last poster); no
// "⚑ cur / max" footer; an unread dot instead of the unread capsule; the flag colour tints the icon, not the row (GAP-026, 027; UXD).
// Density and text size: legacy TopicListRowView (Common.swift:3194-3245 @ 21173e77) and FavoritesListDensity (LOT-169).
/// One topic row: title, flag, counters and last post. Pure display.
struct TopicRowView: View {
    let topic: TopicSummary
    @Environment(\.listDensity) private var density
    @Environment(\.textScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// 1 at the default Dynamic Type size; multiplies the marker size and its offset.
    @ScaledMetric(relativeTo: .body) private var dynamicType: CGFloat = 1

    var body: some View {
        HStack(alignment: .top, spacing: scale.scaled(dynamicType * 8)) {
            if topic.readState == .unread {
                let marker = scale.scaled(dynamicType * density.markerSize)
                Circle().fill(.tint).frame(width: marker, height: marker)
                    .padding(.top, scale.scaled(dynamicType * 6)).accessibilityLabel("Non lu")
            }
            flagIcon.scaledFont(density.titleStyle)
            VStack(alignment: .leading, spacing: density.lineSpacing) {
                Text(topic.title)
                    .scaledFont(density.titleStyle)
                    .fontWeight(topic.readState == .unread ? .semibold : .regular)
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
        }
        .accessibilityElement(children: .combine)
        .listRowInsets(density.rowInsets)
    }

    private var summary: String {
        var parts: [String] = []
        if !topic.starterOrInterlocutors.isEmpty { parts.append(topic.starterOrInterlocutors) }
        parts.append(FrenchPlural.count(topic.repliesCount, "réponse", "réponses"))
        if let date = topic.lastPost?.date { parts.append(date.formatted(.relative(presentation: .named))) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var flagIcon: some View {
        switch topic.flag {
        case .blue: Image(systemName: "flag.fill").foregroundStyle(.blue).accessibilityLabel("Drapeau")
        case .red: Image(systemName: "flag.fill").foregroundStyle(.red).accessibilityLabel("Lu")
        case .yellow: Image(systemName: "star.fill").foregroundStyle(.yellow).accessibilityLabel("Favori")
        case nil: EmptyView()
        }
    }
}
