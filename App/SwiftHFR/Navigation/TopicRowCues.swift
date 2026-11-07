import HFRModels
import SwiftUI

/// The legacy reading cues of a topic row, as pure rules: the unread-pages capsule, the "⚑ cur / max" footer and the row accent (#584).
enum TopicRowCues {
    /// The row accent: the super favourite's orange, or the flag's colour at a lower strength.
    enum Accent: Equatable {
        case superFavorite, yellowFlag, blueFlag, redFlag

        var color: Color {
            switch self {
            case .superFavorite: .orange
            case .yellowFlag: .yellow
            case .blueFlag: .blue
            case .redFlag: .red
            }
        }

        /// Multiplies `RowTint`'s strength: flags are quieter than the super favourite.
        var weight: Double { self == .superFavorite ? 1 : 0.6 }
    }

    /// Pages between the member's flag and the end of the topic (legacy `unreadCount`); nil without a flag, a positive flag page or at 0.
    static func unreadPages(_ topic: TopicSummary) -> Int? {
        guard topic.flag != nil, let current = topic.currentPage, current > 0 else { return nil }
        let behind = topic.pageCount - current
        return behind > 0 ? behind : nil
    }

    /// "⚑ cur / max", with legacy's "≣" for a poll, when the flagged row's page is known and within the topic (legacy `pageLabel`).
    static func pageFooter(_ topic: TopicSummary) -> String? {
        guard topic.flag != nil, let current = topic.currentPage, current > 0, current <= topic.pageCount else { return nil }
        return "⚑\(topic.isPoll ? " \u{2263}" : "") \(current) / \(topic.pageCount)"
    }

    /// Spoken form of the capsule.
    static func unreadPagesLabel(_ pages: Int) -> String {
        FrenchPlural.count(pages, "page non lue", "pages non lues")
    }

    /// The row accent; the super favourite wins over the flag, and the selected row has none (the iPad selection stays visible).
    static func accent(flag: TopicFlag?, isSuperFavorite: Bool, isSelected: Bool) -> Accent? {
        guard !isSelected else { return nil }
        if isSuperFavorite { return .superFavorite }
        switch flag {
        case .yellow: return .yellowFlag
        case .blue: return .blueFlag
        case .red: return .redFlag
        case nil: return nil
        }
    }
}
