import Foundation
import HFRClient
import HFRModels
import Observation
import SwiftUI

// Port of HFRswift/Swift/MessagesView.swift (the avatar menu entries `:205-217`; `presentAvatarActionSheet` `:3610-3616`,
// `openPrivateMessageComposer` `:3533-3547`, `openAvatarPrivateMessage` `:3640-3644`,
// the sent notice `:4299-4304`, `:2602-2605`) @ 2440d79. Differences: the entries open from an anchored menu (issue #595) where
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

/// What the reader says once the MP composer opened from the author menu closes (legacy: "Message privé envoyé"; the
/// Messages list's `newMessageDidClose` for the unconfirmed case). Pure, so the mapping is tested without a view.
enum PrivateMessageFeedback {
    /// The notice for `reason`, nil when the composer closed without a send to report.
    static func text(for reason: ReplyComposerModel.CloseReason) -> String? {
        switch reason {
        case .sent(let result):
            let message = result.message.trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty ? "Message privé envoyé" : message
        case .checkTopic:
            return "Envoi non confirmé : vérifiez vos MP avant de renvoyer."
        case .keptDraft, .discardedDraft, .closedWithoutSaving:
            return nil
        }
    }
}

/// The author menu's state and handlers for one reader (issue #595): the MP composer it opens, and the handlers to register.
/// LOT-118 (#209) adds Blacklist and Whitelist to `handlers` as two more entries; the policy is untouched.
@Observable
@MainActor
final class AuthorMenuFlow {
    /// The new-MP composer opened from the menu, shown as a sheet by `ReaderAuthorMenuSheet`.
    var newMessage: ReplyComposerModel?

    /// Profil (through `reader`'s link router, which alone knows a profile link, LOT-116) and, with a composer, MP.
    /// `reader` is held weakly: the registry lives in it.
    func handlers(
        reader: TopicReaderModel, composer: ComposerServices?, openProfile: @escaping @MainActor (Int) -> Void
    ) -> [any MessageActionHandler] {
        var handlers: [any MessageActionHandler] = [
            ProfileActionHandler { [weak reader] url in
                guard case .profile(let id)? = reader?.action(forLink: url, defaultBrowser: false) else { return }
                openProfile(id)
            }
        ]
        if let composer {
            handlers.append(PrivateMessageActionHandler { [weak self] target in
                self?.newMessage = ReplyComposerModel(composing: .newPrivateMessage(target), services: composer)
            })
        }
        return handlers
    }
}

/// The MP composer sheet of the author menu; its close reason becomes the reader's confirmation.
struct ReaderAuthorMenuSheet: ViewModifier {
    @Bindable var flow: AuthorMenuFlow
    let model: TopicReaderModel

    func body(content: Content) -> some View {
        content.sheet(item: $flow.newMessage) { message in
            ReplyComposerView(model: message) { reason in
                guard let text = PrivateMessageFeedback.text(for: reason) else { return }
                model.showMenuFeedback(text)
                AccessibilityNotification.Announcement(text).post()
            }
        }
    }
}
