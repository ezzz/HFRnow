import Foundation
import HFRModels

// Port of HFRswift/Swift/MessagesView.swift (the avatar menu entries `:205-217`; `presentAvatarActionSheet` `:3610-3616`,
// `openPrivateMessageComposer` `:4208-4224`) @ 2440d79. Differences: the entries open from an anchored menu (issue #595) where
// legacy jumped to the profile screen when the message had a profile link; the profile is fetched without cookies (LOT-116);
// Blacklist and Whitelist wait for LOT-118 (#209), so they are not offered (GAP-064).

/// "Profil" in the author menu: opens the member's profile screen from the message's profile link (LOT-116).
@MainActor
struct ProfileActionHandler: MessageActionHandler {
    /// Opens the profile of the member `url` names; the reader's link router decides, so a link that is no profile does nothing.
    let open: @MainActor (URL) -> Void

    var kind: MessageMenuAction.Kind { .profile }

    func isAvailable(for context: MessageMenuContext) -> Bool { context.actions.profileURL != nil }

    func perform(with context: MessageMenuContext) async {
        guard let url = context.actions.profileURL else { return }
        open(url)
    }
}

/// "MP" in the author menu: the new-MP composer addressed to the member, from the message's private-message link (LOT-128).
/// Registered only with a composer (a logged-in account); the link must be a forum private-message page.
@MainActor
struct PrivateMessageActionHandler: MessageActionHandler {
    /// Opens the composer for `target`.
    let open: @MainActor (NewMessageTarget) -> Void

    var kind: MessageMenuAction.Kind { .privateMessage }

    func isAvailable(for context: MessageMenuContext) -> Bool { Self.target(of: context) != nil }

    func perform(with context: MessageMenuContext) async {
        guard let target = Self.target(of: context) else { return }
        open(target)
    }

    /// The composer's target; nil for a message without link or whose link leaves the forum or is not a private message.
    static func target(of context: MessageMenuContext) -> NewMessageTarget? {
        context.actions.privateMessageURL.flatMap { NewMessageTarget(link: $0) }
    }
}
