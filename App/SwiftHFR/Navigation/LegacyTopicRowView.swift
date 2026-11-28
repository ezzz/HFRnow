import HFRModels
import SwiftUI

// Port of HFRswift/Swift/Common.swift (TopicListRowView, :3608-3650) and MainWindow.swift (footerLeft/footerRight, :455-504) @ 87fe0d1c.
// Differences: the date is formatted from the parsed `Date` (`TopicRowInfoLine`), the tint is drawn by `rowPill` around this view
// (GAP-026, 027; #817, #857); the pin and lock are not coloured per theme yet; the footer's two sides are stacked at accessibility
// sizes (#1439; legacy keeps them side by side at every size).
/// The default topic row, as legacy draws it: no flag or star before the title, no reply count, no starter.
struct LegacyTopicRowView: View {
    let topic: TopicSummary
    /// A super favourite of the account: its tint is drawn around the row; VoiceOver says it.
    var isSuperFavorite = false
    /// The row's flag colour is drawn as a tint around it (`TopicListView.rowTint`): VoiceOver says the flag.
    var flagIsTinted = false
    var markedRead = false
    var showsFlag = true
    @Environment(\.listDensity) private var density
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isUnread: Bool { topic.readState == .unread && !markedRead }

    /// What the dense row's marks said and this row shows by weight or tint only (colour is never the only cue).
    private var spokenState: String {
        [
            isUnread ? "Non lu" : nil, isSuperFavorite ? "Super favori" : nil,
            flagIsTinted && showsFlag ? TopicRowCues.flagLabel(topic.flag) : nil
        ].compactMap { $0 }.joined(separator: ", ")
    }

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
            infoLine.scaledFont(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(spokenState)
        .listRowInsets(density.rowInsets)
    }

    /// Legacy's footer, « ⚑ lue / total » on the left and « last poster - date » on the right. At accessibility sizes the two sides
    /// are stacked and the date may wrap (#1439: side by side, the right side lost its date to the ellipsis and « 452 / 452 » wrapped).
    @ViewBuilder private var infoLine: some View {
        let leading = Text(TopicRowInfoLine.leading(topic, showsFlag: showsFlag))
            .accessibilityLabel(TopicRowInfoLine.spokenLeading(topic, showsFlag: showsFlag))
        let trailing = TopicRowInfoLine.trailing(topic)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: density.lineSpacing) {
                leading
                // At its ideal height: in the Favoris list it got one line and lost the date (#1439, seen on the simulator only).
                if let trailing { Text(trailing).fixedSize(horizontal: false, vertical: true) }
            }
        } else {
            HStack(spacing: 6) {
                leading
                Spacer(minLength: 0)
                if let trailing { Text(trailing).lineLimit(1) }
            }
        }
    }
}
