import Foundation

// Port of HFRswift/Swift/MessagesView.swift (the per-action entries built in the popup, `:1722-1775`) @ 2440d79.
// Differences: GAP-064; each action goes to a handler registered by its own lot instead of a `parent.on…Request` closure,
// and an action without a handler is hidden.

/// What a lot implements to plug one action into the message menu (alert, AQ, bookmark, BL/WL, flag, edit, delete, quote,
/// profile, MP). Registering a handler is the only change: the policy is not edited.
@MainActor
protocol MessageActionHandler {
    /// The action this handler serves.
    var kind: MessageMenuAction.Kind { get }
    /// Whether the action applies to `context`, on top of the policy (legacy `canAQ`, `canBookmark`); true by default.
    func isAvailable(for context: MessageMenuContext) -> Bool
    /// Runs the action the user picked.
    func perform(with context: MessageMenuContext) async
}

extension MessageActionHandler {
    func isAvailable(for context: MessageMenuContext) -> Bool { true }
}

/// The handlers of the merged lots. An action whose lot is not merged has no handler and is hidden, never shown disabled.
@MainActor
struct MessageActionRegistry {
    private var handlers: [MessageMenuAction.Kind: any MessageActionHandler] = [:]

    /// A registry holding `handlers`; the last one wins for a kind.
    init(_ handlers: [any MessageActionHandler] = []) {
        for handler in handlers { self.handlers[handler.kind] = handler }
    }

    /// The actions of the author menu (legacy avatar popup); every other action belongs to the message menu.
    private static let authorKinds: Set<MessageMenuAction.Kind> = [.profile, .privateMessage, .blocklist, .allowlist]

    /// Whether any action of `source`'s menu is implemented (no button for a menu that could never open).
    func offers(_ source: MessageMenuSource) -> Bool {
        handlers.keys.contains { Self.authorKinds.contains($0) == (source == .avatar) }
    }

    /// The entries the menu shows for `context`: the policy's, minus those without a handler or that the handler declines.
    func entries(for context: MessageMenuContext, source: MessageMenuSource) -> [MessageMenuAction] {
        var context = context
        // AQ (quality alert) and bookmark are offered by their lot's handler, not derived from the page.
        context.canQualityAlert = handlers[.qualityAlert]?.isAvailable(for: context) ?? false
        context.canBookmark = handlers[.bookmark]?.isAvailable(for: context) ?? false
        return MessageMenuPolicy.orderedActions(for: context, source: source).filter { action in
            handlers[action.kind]?.isAvailable(for: context) ?? false
        }
    }

    /// Runs `action` through its handler; false when there is none (a stale menu).
    @discardableResult
    func perform(_ action: MessageMenuAction, with context: MessageMenuContext) async -> Bool {
        guard let handler = handlers[action.kind], handler.isAvailable(for: context) else { return false }
        await handler.perform(with: context)
        return true
    }
}

/// "Link": copies the message's permalink (the only action implemented by LOT-087 itself).
@MainActor
struct LinkActionHandler: MessageActionHandler {
    /// Puts the URL on the pasteboard (the view's side effect, replaced in tests).
    let copy: @MainActor (URL) -> Void
    /// Tells the user the link was copied.
    let confirm: @MainActor (String) -> Void

    var kind: MessageMenuAction.Kind { .link }

    func isAvailable(for context: MessageMenuContext) -> Bool { context.permalinkURL != nil }

    func perform(with context: MessageMenuContext) async {
        guard let url = context.permalinkURL else { return }
        copy(url)
        confirm("Lien copié")
    }
}
