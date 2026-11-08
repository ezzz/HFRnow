import SwiftUI
import UIKit

// Port of HFRswift/Swift/Common.swift (TopicListRowView title, `.foregroundStyle(isVisited ? .secondary : .primary)`, :3119-3120)
// and MPListView.swift (MPRowView, `titleWeight`, :469) @ 2440d79. Differences: in light the read title keeps the secondary
// label's Increase Contrast strength, since the standard one measures 3.4:1 on the white card (#651, GAP-227).
/// How a conversation title is drawn: an unread one stands out (primary colour, semibold), a read one fades (secondary
/// colour, regular), as in legacy (#651).
enum MessageTitleTone: Equatable {
    case primary, secondary

    /// The tone of a conversation the member has (not) read.
    static func of(isUnread: Bool) -> MessageTitleTone { isUnread ? .primary : .secondary }

    /// Semibold when unread, regular when read (legacy `MPListView.swift:469`).
    var weight: Font.Weight { self == .primary ? .semibold : .regular }

    /// The colour of the title.
    var style: AnyShapeStyle {
        switch self {
        case .primary: AnyShapeStyle(.primary)
        case .secondary: AnyShapeStyle(ReadTitleStyle())
        }
    }
}

/// The secondary colour of a read title, held at 4.5:1 or more on the list's card in every theme (#651).
///
/// On a prominent background (the iPad's accent selection) it is the system's hierarchical `.secondary`, which the system
/// lightens for that background; elsewhere it is `color(for:)`.
struct ReadTitleStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
        environment.backgroundProminence == .increased ? AnyShapeStyle(.secondary) : AnyShapeStyle(Self.color)
    }

    /// `color(for:)` as a dynamic colour, resolved per scheme and contrast.
    static let color = Color(uiColor: UIColor { color(for: $0) })

    /// The secondary label in dark (6:1 on the card, 7.1:1 with Increase Contrast); in light, the secondary label at its
    /// Increase Contrast strength whatever the setting (6:1): the standard light one, legacy's `.secondary`, is 3.4:1 on white.
    static func color(for traits: UITraitCollection) -> UIColor {
        guard traits.userInterfaceStyle != .dark else { return UIColor.secondaryLabel.resolvedColor(with: traits) }
        return UIColor.secondaryLabel.resolvedColor(with: traits.modifyingTraits { $0.accessibilityContrast = .high })
    }
}
