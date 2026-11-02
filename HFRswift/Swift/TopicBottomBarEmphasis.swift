//
//  TopicBottomBarEmphasis.swift
//  HFRswift
//

/// The single bottom-bar button of a topic that carries the prominent (tinted) style.
///
/// Apple HIG, Toolbars: "Only specify one primary action". Before 4.0.5 the topic bottom bar
/// could show several prominent buttons at once, and at the bottom of the last page the most
/// visible one was Actualiser rather than Répondre (feedback from Bybifok / moust4ki).
/// Actualiser is never prominent; it stays available as a plain button at the bottom of the
/// last page (the topic web view has no pull-to-refresh).
enum TopicBottomBarEmphasis: Equatable {
    /// "Résultat suivant" while browsing search results inside a topic.
    case searchNext
    /// Next page, at the bottom of an intermediate page (end-of-page cue kept from HFR-008).
    case nextPage
    /// Répondre: the primary action of a topic when no navigation cue applies.
    case reply
    /// Nothing is prominent (reply button hidden by the setting or by the layout).
    case none

    /// Resolves the prominent button, in priority order: search, next page, reply.
    /// - Parameters:
    ///   - isInSearchMode: the topic is opened from a search, with a "Résultat suivant" button.
    ///   - isNextPagePromoted: the reader is at the bottom of a page that is not the last one.
    ///   - isReplyButtonVisible: the Répondre button is shown in the bottom bar.
    static func resolve(
        isInSearchMode: Bool,
        isNextPagePromoted: Bool,
        isReplyButtonVisible: Bool
    ) -> TopicBottomBarEmphasis {
        if isInSearchMode {
            return .searchNext
        }
        if isNextPagePromoted {
            return .nextPage
        }
        if isReplyButtonVisible {
            return .reply
        }
        return .none
    }
}
