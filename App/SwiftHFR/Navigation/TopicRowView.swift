import HFRModels
import SwiftUI

/// One topic row: title, flag, counters and last post. Pure display.
struct TopicRowView: View {
    let topic: TopicSummary

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            flagIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title)
                    .font(.body)
                    .fontWeight(topic.readState == .unread ? .semibold : .regular)
                    .lineLimit(3)
                HStack(spacing: 6) {
                    if topic.isSticky { Image(systemName: "pin.fill").accessibilityLabel("Post-it") }
                    if topic.isClosed { Image(systemName: "lock.fill").accessibilityLabel("Fermé") }
                    if topic.isPoll { Image(systemName: "chart.bar.fill").accessibilityLabel("Sondage") }
                    Text(summary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        var parts: [String] = []
        if !topic.starterOrInterlocutors.isEmpty { parts.append(topic.starterOrInterlocutors) }
        parts.append("\(topic.repliesCount) réponses")
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
