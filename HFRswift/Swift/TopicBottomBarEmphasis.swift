//
//  TopicBottomBarEmphasis.swift
//  HFRswift
//

/// The single button of the paginated topic bottom bar that carries the prominent (tinted) style.
/// The one-button bars (favorite post filter, filtered search) keep their own prominent button.
///
/// Apple HIG, Toolbars: "Only specify one primary action". Before 4.0.5 the bar could show
/// several prominent buttons at once, and at the bottom of the last page the most visible one
/// was Actualiser rather than Répondre.
///
/// The choice only depends on stable state (search mode, reply setting, layout), never on the
/// scroll position: the prominent button must not jump between two buttons while reading.
/// Actualiser and the next page button are never prominent; Actualiser stays available as a
/// plain button at the bottom of the last page (the topic web view has no pull-to-refresh).
enum TopicBottomBarEmphasis: Equatable {
    /// "Résultat suivant" while browsing search results inside a topic.
    case searchNext
    /// Répondre: the primary action of a topic.
    case reply
    /// Nothing is prominent (reply button hidden by the setting or by the layout).
    case none

    /// Resolves the prominent button, in priority order: search, reply.
    /// - Parameters:
    ///   - isInSearchMode: the topic is opened from a search, with a "Résultat suivant" button.
    ///   - isReplyButtonVisible: the Répondre button is shown in the bottom bar.
    static func resolve(
        isInSearchMode: Bool,
        isReplyButtonVisible: Bool
    ) -> TopicBottomBarEmphasis {
        if isInSearchMode {
            return .searchNext
        }
        if isReplyButtonVisible {
            return .reply
        }
        return .none
    }
}
