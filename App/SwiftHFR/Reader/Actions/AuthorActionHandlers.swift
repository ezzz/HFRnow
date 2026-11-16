import Foundation
import HFRClient
import HFRModels
import HFRParsing
import Observation
import SwiftUI

// Port of HFRswift/Swift/MessagesView.swift (the avatar menu entries `:205-217`; `presentAvatarActionSheet` `:3610-3616`,
// `openPrivateMessageComposer` `:3533-3547`, `openAvatarPrivateMessage` `:3640-3644`,
// the sent notice `:4299-4304`, `:2602-2605`) @ 2440d79, and of the profile opened from a message (`presentAvatarActionSheet`
// `:4415-4420`, `userProfileQuickActions` `:4387-4412`, `dismissUserProfile(then:)` `:4422-4490`) @ 87fe0d1c. Differences: as
// legacy, a tap on the author opens the profile when the message links to it (#652, which reverses #595's menu-first choice), and
// the author menu, anchored at the author rather than a sheet, only otherwise (GAP-064); the profile is fetched without cookies
// (LOT-116, GAP-167); Blacklist and Whitelist are `PseudoListActionHandler` (LOT-118).

/// "Profil" in the author menu, and what a tap on the author runs when the message has a profile link (#652): opens the
/// member's profile screen (LOT-116) for that message.
@MainActor
struct ProfileActionHandler: MessageActionHandler {
    /// Opens the profile `url` names, for the message `context` describes.
    let open: @MainActor (URL, MessageMenuContext) -> Void

    var kind: MessageMenuAction.Kind { .profile }

    /// Only a forum profile link (LOT-095's router): any other link leaves the author menu to the tap, as legacy's sheet without
    /// a profile.
    func isAvailable(for context: MessageMenuContext) -> Bool { context.actions.profileMemberID != nil }

    func perform(with context: MessageMenuContext) async {
        guard let url = context.actions.profileURL, context.actions.profileMemberID != nil else { return }
        open(url, context)
    }
}

extension MessageActions {
    /// The member the message's profile link names (LOT-095's router); nil without a link or for a link that is no profile.
    /// A tap on the author opens that profile (#652), and the author menu only when this is nil.
    var profileMemberID: Int? {
        guard let profileURL, case .profile(let memberID) = HFRLinkRoute.route(for: profileURL) else { return nil }
        return memberID
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

/// The author's state and handlers for one reader (issues #595, #652): the profile sheet, the MP composer, and the handlers to
/// register. Blacklist and Whitelist are `PseudoListActionHandler` (LOT-118); the policy is untouched.
@Observable
@MainActor
final class AuthorMenuFlow {
    /// The new-MP composer opened from the menu or the profile, shown by `ReaderAuthorMenuSheet`.
    var newMessage: ReplyComposerModel?
    /// The profile sheet: from a profile link in a message, or from a message's author (#652).
    var profile: UserProfileModel?
    /// What runs once the profile sheet is gone (legacy `dismissUserProfile(then:)`, `MessagesView.swift:4422-4436` @
    /// 87fe0d1c): a sheet cannot open while another closes.
    @ObservationIgnored private var afterProfile: (@MainActor () -> Void)?

    /// Profil (through `reader`'s link router, LOT-116) and, with a composer, MP. `makeProfile` builds the profile screen's model
    /// of a member (`ReaderServices.profileModel`); `confirm` tells the user the result of a list toggle made on it.
    /// `reader` is held weakly: the registry lives in it.
    func handlers(
        reader: TopicReaderModel, composer: ComposerServices?, makeProfile: @escaping @MainActor (Int) -> UserProfileModel,
        confirm: @escaping @MainActor (String) -> Void
    ) -> [any MessageActionHandler] {
        var handlers: [any MessageActionHandler] = [
            ProfileActionHandler { [weak self, weak reader] url, context in
                guard let self, case .profile(let id)? = reader?.action(forLink: url, defaultBrowser: false) else { return }
                self.showProfile(makeProfile(id), from: context, composer: composer, confirm: confirm)
            }
        ]
        if let composer {
            handlers.append(PrivateMessageActionHandler { [weak self] target in
                self?.newMessage = ReplyComposerModel(composing: .newPrivateMessage(target), services: composer)
            })
        }
        return handlers
    }

    /// Shows `model`, the profile of `context`'s author, with legacy's quick actions (`userProfileQuickActions`,
    /// `MessagesView.swift:4387-4412` @ 87fe0d1c): MP to the message's private-message link when not the user's own post and a
    /// composer exists; the lists on the author's pseudo. "MP" and a toggle close the profile first, then open the composer or
    /// tell the result (`:4422-4490`).
    func showProfile(
        _ model: UserProfileModel, from context: MessageMenuContext, composer: ComposerServices?,
        confirm: @escaping @MainActor (String) -> Void
    ) {
        model.origin = ProfileMessageOrigin(author: context.author, isOwnMessage: context.isOwnMessage)
        if let composer, !context.isOwnMessage, let target = PrivateMessageActionHandler.target(of: context) {
            model.onPrivateMessage = { [weak self] _ in
                self?.closeProfile { [weak self] in
                    self?.newMessage = ReplyComposerModel(composing: .newPrivateMessage(target), services: composer)
                }
            }
        }
        model.onListToggled = { [weak self] text in self?.closeProfile { confirm(text) } }
        show(model)
    }

    /// Shows `model` with nothing pending from an earlier profile (a profile link in a message body opens through here too).
    func show(_ model: UserProfileModel) {
        afterProfile = nil
        profile = model
    }

    /// Closes the profile sheet, then runs `next` once it is gone (`profileDidClose`); at once when the user already closed it
    /// (a toggle that ends after "Fermer"), so nothing waits for a dismissal that will not come.
    func closeProfile(then next: @escaping @MainActor () -> Void) {
        guard profile != nil else {
            afterProfile = nil
            next()
            return
        }
        afterProfile = next
        profile = nil
    }

    /// The profile sheet is gone (its `onDismiss`): runs what closing it was for, once.
    func profileDidClose() {
        let next = afterProfile
        afterProfile = nil
        next?()
    }
}

/// The MP composer of the author menu (docked on an iPhone, a sheet on an iPad: `ReaderComposerPresenter`); its close reason
/// becomes the reader's confirmation.
struct ReaderAuthorMenuSheet: ViewModifier {
    @Bindable var flow: AuthorMenuFlow
    let model: TopicReaderModel

    func body(content: Content) -> some View {
        // EXPERIMENTAL(modernComposer, #904): replaces the composer sheet by `ReaderComposerPresenter`, which docks it on the
        // keyboard with the option on (#853) and shows the same sheet with it off.
        content.modifier(ReaderComposerPresenter(composer: $flow.newMessage) { _, reason in
            guard let text = PrivateMessageFeedback.text(for: reason) else { return }
            model.showMenuFeedback(text) // the toast announces itself
        })
        // The page under the composer scrolls but ignores its taps while it is open (#653).
        .onChange(of: flow.newMessage != nil) { _, isOpen in model.composer(.privateMessage, isOpen: isOpen) }
    }
}
