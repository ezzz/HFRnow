import HFRModels
import SwiftUI

// The dense row (`DenseTopicRowView`, Experimental/DenseRows/) is the switch-on path of Réglages › Expérimental › « Lignes denses ».
/// Which row the lists draw.
enum TopicRowStyle {
    /// Legacy's row (default): pin and lock before the title, unread-pages pill, "⚑ lue / total" and "dernier posteur - date".
    case legacy
    /// The dense row, behind Réglages › Expérimental › « Lignes denses » (#905).
    case dense

    /// EXPERIMENTAL(denseRows, #905): the switch point; off (or no settings in the environment), legacy's row.
    @MainActor static func current(_ experimental: ExperimentalSettings?) -> TopicRowStyle {
        ExperimentalSettings.isOn(.denseRows, in: experimental) ? .dense : .legacy
    }
}

/// One topic row, in the current style. Pure display.
struct TopicRowView: View {
    let topic: TopicSummary
    var isSuperFavorite = false
    var markedRead = false
    var showsFlag = true
    /// The flag colour is drawn as a row tint (`TopicListView.rowTint`).
    var flagIsTinted = false
    @Environment(ExperimentalSettings.self) private var experimental: ExperimentalSettings?

    var body: some View {
        switch countingBuild(TopicRowStyle.current(experimental)) {
        case .legacy:
            LegacyTopicRowView(
                topic: topic, isSuperFavorite: isSuperFavorite, flagIsTinted: flagIsTinted, markedRead: markedRead, showsFlag: showsFlag
            )
        case .dense: DenseTopicRowView(topic: topic, isSuperFavorite: isSuperFavorite, markedRead: markedRead, showsFlag: showsFlag)
        }
    }
}
