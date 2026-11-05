import Foundation
import HFRModels

// Port of HFRswift/Swift/MessagesView.swift (MessagePopupMenuActionKind, MessagePopupMenuPolicy) @ 2440d79.
// Differences: GAP-064 (and GAP-051 for the header: a "⋯" button instead of the legacy "+", a UX change to confirm, UXD-09); the legacy `TopicPageMessageActions` flags that LOT-031 does not port
// (`isOwnMessage`, `canBeFavorite`, `canDelete`) are derived in `MessageMenuContext`; `canQualityAlert` and `canBookmark` are
// offered by the handler of their own lot (docs/lots/LOT-087-message-actions.md).

/// Where on a message the user opened the menu: the message itself or its author (avatar and pseudo).
enum MessageMenuSource: String, Equatable, Sendable {
    case message
    case avatar
}

/// An entry of the message menu (legacy `MessagePopupMenuActionKind`, 13 actions, same titles).
struct MessageMenuAction: Equatable, Sendable {
    /// What a handler is registered for: the action without its display state.
    enum Kind: Hashable, Sendable, CaseIterable {
        case quote, quoteSelection, edit, profile, privateMessage, blocklist, allowlist
        case favorite, link, alert, qualityAlert, bookmark, delete
    }

    /// Title, symbol and menu position of a kind; one table, so a new action cannot miss one of them.
    private struct Presentation {
        let title: String
        let symbol: String
        let priority: Int
    }

    // Titles are legacy's, in French ("Link" stays "Link", Bybifok PR #3 note). Priorities are legacy's `priority(for:)`.
    private static let presentations: [Kind: Presentation] = [
        .quote: Presentation(title: "Citer", symbol: "quote.bubble", priority: 0),
        .quoteSelection: Presentation(title: "Citer ☐", symbol: "text.quote", priority: 1),
        .edit: Presentation(title: "Editer", symbol: "square.and.pencil", priority: 2),
        .profile: Presentation(title: "Profil", symbol: "person.crop.circle", priority: 3),
        .privateMessage: Presentation(title: "MP", symbol: "message", priority: 4),
        .blocklist: Presentation(title: "Blacklist", symbol: "hand.raised", priority: 5),
        .allowlist: Presentation(title: "Whitelist", symbol: "heart", priority: 6),
        .favorite: Presentation(title: "Favoris", symbol: "star", priority: 7),
        .link: Presentation(title: "Link", symbol: "link", priority: 8),
        .alert: Presentation(title: "Alerter", symbol: "exclamationmark.bubble", priority: 9),
        .qualityAlert: Presentation(title: "AQ", symbol: "bubble.left.and.exclamationmark.bubble.right", priority: 10),
        .bookmark: Presentation(title: "Bookmark", symbol: "bookmark", priority: 11),
        .delete: Presentation(title: "Supprimer", symbol: "trash", priority: 12)
    ]

    /// The action without its display state.
    let kind: Kind
    /// Multi-quote only: the message is in the selection.
    let isSelected: Bool

    /// An action of `kind`, not selected.
    init(kind: Kind, isSelected: Bool = false) {
        self.kind = kind
        self.isSelected = isSelected
    }

    static let quote = MessageMenuAction(kind: .quote)
    static let edit = MessageMenuAction(kind: .edit)
    static let profile = MessageMenuAction(kind: .profile)
    static let privateMessage = MessageMenuAction(kind: .privateMessage)
    static let blocklist = MessageMenuAction(kind: .blocklist)
    static let allowlist = MessageMenuAction(kind: .allowlist)
    static let favorite = MessageMenuAction(kind: .favorite)
    static let link = MessageMenuAction(kind: .link)
    static let alert = MessageMenuAction(kind: .alert)
    static let qualityAlert = MessageMenuAction(kind: .qualityAlert)
    static let bookmark = MessageMenuAction(kind: .bookmark)
    static let delete = MessageMenuAction(kind: .delete)

    /// Multi-quote, with its state.
    static func quoteSelection(isSelected: Bool) -> MessageMenuAction {
        MessageMenuAction(kind: .quoteSelection, isSelected: isSelected)
    }

    /// Menu title; multi-quote shows its state ("Citer ☑" / "Citer ☐").
    var title: String {
        if kind == .quoteSelection { return isSelected ? "Citer ☑" : "Citer ☐" }
        return Self.presentations[kind]?.title ?? ""
    }

    /// SF Symbol of the entry.
    var systemImageName: String { Self.presentations[kind]?.symbol ?? "questionmark" }

    /// Only the deletion is destructive.
    var isDestructive: Bool { kind == .delete }

    /// Position in the menu: quote, multi-quote, edit, then the author's, then the rest.
    var priority: Int { Self.presentations[kind]?.priority ?? Int.max }
}

/// Everything the menu policy reads about one message.
struct MessageMenuContext: Equatable, Sendable {
    /// Message number (`numreponse`).
    var numreponse: Int
    /// Author pseudo, untrusted text.
    var author: String
    /// The action links LOT-031 parsed from the message's toolbar (nil = HFR offers nothing).
    var actions: MessageActions
    /// Link to the message on its page (`<page URL>#t<numreponse>`); nil when the page URL is unknown.
    var permalinkURL: URL?
    /// The topic's first message: legacy never offers its deletion, and on HFR it deletes the whole topic (HFR-PROTOCOL §3.1).
    var isFirstPostOfTopic = false
    /// Multi-quote state of the message (legacy cookie `quotes…`): LOT-086 owns it, false until then.
    var isQuoteSelectionEnabled = false
    /// The message is the user's own: HFR only gives an edit link on those (LOT-031 decision 5, legacy `isOwnMessage`).
    var isOwnMessage: Bool { actions.editURL != nil }
    /// The flag link of the topic is present (legacy `canBeFavorite`, derived: LOT-031 drops the flag).
    var canBeFavorite: Bool { actions.favoriteURL != nil }
    /// Deleting is the edit form with `delete=1`: needs the edit link, never offered on the topic's first message.
    var canDelete: Bool { actions.editURL != nil && !isFirstPostOfTopic }
    /// Set by the AQ handler (LOT-134); false without one.
    var canQualityAlert = false
    /// Set by the bookmark handler (LOT-132); false without one.
    var canBookmark = false
}

/// The pure menu policy (legacy `MessagePopupMenuPolicy.orderedActionKinds`): which actions a message offers and in which
/// order. It knows nothing of handlers; `MessageActionRegistry` hides what no merged lot implements.
enum MessageMenuPolicy {
    /// The actions offered for `source`, in menu order (stable for equal priorities).
    static func orderedActions(for context: MessageMenuContext, source: MessageMenuSource) -> [MessageMenuAction] {
        let actions = source == .avatar ? authorActions(for: context) : messageActions(for: context)
        return actions.enumerated().sorted { lhs, rhs in
            lhs.element.priority != rhs.element.priority ? lhs.element.priority < rhs.element.priority : lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func authorActions(for context: MessageMenuContext) -> [MessageMenuAction] {
        var actions: [MessageMenuAction] = []
        if context.actions.profileURL != nil { actions.append(.profile) }
        if !context.isOwnMessage, context.actions.privateMessageURL != nil { actions.append(.privateMessage) }
        if !context.isOwnMessage, !context.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            actions.append(.blocklist)
            actions.append(.allowlist)
        }
        return actions
    }

    private static func messageActions(for context: MessageMenuContext) -> [MessageMenuAction] {
        var actions: [MessageMenuAction] = []
        let links = context.actions
        if links.quoteURL != nil { actions.append(.quote) }
        if links.quoteSelection != nil { actions.append(.quoteSelection(isSelected: context.isQuoteSelectionEnabled)) }
        if context.canBeFavorite { actions.append(.favorite) }
        if context.permalinkURL != nil { actions.append(.link) }
        // Legacy: without an alert form, the alert falls back to the permalink (a mail); one entry either way.
        if !context.isOwnMessage, links.alertURL != nil || context.permalinkURL != nil { actions.append(.alert) }
        if context.canQualityAlert { actions.append(.qualityAlert) }
        if context.canBookmark { actions.append(.bookmark) }
        if links.editURL != nil { actions.append(.edit) }
        if context.canDelete { actions.append(.delete) }
        return actions
    }
}
