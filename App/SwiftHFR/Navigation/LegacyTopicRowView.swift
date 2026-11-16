import HFRModels
import SwiftUI

// Port of HFRswift/Swift/Common.swift (TopicListRowView, :3608-3650) and MainWindow.swift (footerLeft/footerRight, :455-504) @ 87fe0d1c.
// Differences: the date is formatted from the parsed `Date` (`TopicRowInfoLine`), the tint is drawn by `rowPill` around this view
// (GAP-026, 027; #817, #857); the pin and lock are not coloured per theme yet.
/// The default topic row, as legacy draws it: no flag or star before the title, no reply count, no starter.
struct LegacyTopicRowView: View {
    let topic: TopicSummary
    var markedRead = false
    var showsFlag = true
    @Environment(\.listDensity) private var density
    @Environment(\.textScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isUnread: Bool { topic.readState == .unread && !markedRead }

    var body: some View {
        VStack(alignment: .leading, spacing: density.lineSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if topic.isSticky { Image(systemName: "pin.fill").foregroundStyle(.red).accessibilityLabel("Post-it") }
                if topic.isClosed { Image(systemName: "lock.fill").foregroundStyle(.secondary).accessibilityLabel("Fermé") }
                Text(topic.displayTitle)
                    .scaledFont(density.titleStyle)
                    .fontWeight(isUnread ? .semibold : .regular)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                Spacer(minLength: 0)
                if showsFlag, let pages = TopicRowCues.unreadPages(topic) {
                    BadgeCapsule(text: "\(pages)", isBold: true).accessibilityLabel(TopicRowCues.unreadPagesLabel(pages))
                }
            }
            HStack(spacing: 6) {
                Text(TopicRowInfoLine.leading(topic, showsFlag: showsFlag))
                Spacer(minLength: 0)
                if let trailing = TopicRowInfoLine.trailing(topic) { Text(trailing).lineLimit(1) }
            }
            .scaledFont(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .listRowInsets(density.rowInsets)
    }
}
