import HFRModels
import SwiftUI

// Moved from App/SwiftHFR/Navigation/TopicRowView.swift (#903) unchanged; port pointer of the row: `TopicRowView` (GAP-026, 027).
/// Today's leading marks of a topic row (#905, behind Réglages › Expérimental › « Lignes avec icônes de drapeau », #903): the
/// unread dot and the flag icon before the title. #817 builds the legacy rows (the whole row tinted by flag type, no icon before
/// the title) as the switch-off path; this folder keeps these marks for the switch-on path.
enum FlagIconRows {
    /// The flag icon of a row: its symbol, colour and VoiceOver label.
    struct FlagMark: Equatable {
        let symbol: String
        let color: Color
        let label: String
    }

    /// The flag icon before the title; nil without a flag.
    static func flagMark(_ flag: TopicFlag?) -> FlagMark? {
        switch flag {
        case .blue: FlagMark(symbol: "flag.fill", color: Color.blue, label: "Drapeau")
        case .red: FlagMark(symbol: "flag.fill", color: Color.red, label: "Lu")
        case .yellow: FlagMark(symbol: "star.fill", color: Color.yellow, label: "Favori")
        case nil: nil
        }
    }
}

/// The unread dot before the title, in the tint colour, sized by the list density, the text size and Dynamic Type.
struct UnreadDotMark: View {
    @Environment(\.listDensity) private var density
    @Environment(\.textScale) private var scale
    /// 1 at the default Dynamic Type size; multiplies the marker size and its offset.
    @ScaledMetric(relativeTo: .body) private var dynamicType: CGFloat = 1

    var body: some View {
        let marker = scale.scaled(dynamicType * density.markerSize)
        Circle().fill(.tint).frame(width: marker, height: marker)
            .padding(.top, scale.scaled(dynamicType * 6)).accessibilityLabel("Non lu")
    }
}

/// The flag icon before the title: a blue or red flag, or the yellow star of a favourite.
struct FlagIconMark: View {
    let flag: TopicFlag?

    var body: some View {
        if let mark = FlagIconRows.flagMark(flag) {
            Image(systemName: mark.symbol).foregroundStyle(mark.color).accessibilityLabel(mark.label)
        }
    }
}
