import CoreGraphics
import Foundation
import HFRModels
import HFRNetwork
import Observation

// Port of HFRswift/Swift/MessagesView.swift (presentPopupMenu `:2011-2058` and the author menu, in the favourite post filter
// mode `renderFavoritePostFilterResult` `:4767-4791`) @ 87fe0d1c. Differences: docs/lots/LOT-159-app-review-ugc.md, R12 and
// difference 3: only the UGC entries ("Link", "Alerter", "Blacklist", "Whitelist") in LOT-114's read-only sheet; the posts are
// read cookie-less, so "Alerter" is the moderators' mail and the user's own posts are found by pseudo, not by an edit link.
/// The message and author menus of the filtered posts sheet (LOT-159): every message read there can be reported and its
/// author blocked, as in the reader (App Review guideline 1.2).
@MainActor
@Observable
final class FilteredPostsMenuModel: MenuFeedbackShowing {
    /// The confirmation of the last action ("Lien copié", the lists' sentences).
    private(set) var menuFeedback: String?
    /// Bumped by each confirmation, so a repeated text is shown and announced again.
    private(set) var menuFeedbackSerial = 0
    /// Bumped when an action changed the pseudo lists: the sheet builds its document again, so a blocked author's posts hide.
    private(set) var listsRevision = 0
    /// « Connectez-vous pour bloquer » was picked: the sheet opens the login (LOT-159 D3); the view clears it when it closes.
    var wantsSignIn = false
    /// "Alerter": the mail to the moderators (LOT-135's fallback), with its confirmation alert.
    private(set) var alerts: ModeratorAlertModel?

    @ObservationIgnored private var registry = MessageActionRegistry()
    @ObservationIgnored private let lists: PseudoListManager?
    /// The reader's display settings, the pseudo lists included (read at each build).
    @ObservationIgnored private let baseOptions: @Sendable () -> ReaderRenderOptions

    /// The menus over `services` (the lists and the moderators' address of the session); `copy` puts a link on the pasteboard,
    /// `openMail` hands the alert mail to the system.
    init(
        services: ReaderServices, copy: @escaping @MainActor (URL) -> Void, openMail: @escaping @MainActor (URL) -> Void
    ) {
        lists = services.pseudoLists
        baseOptions = services.settings.renderOptions
        let confirm: @MainActor (String) -> Void = { [weak self] text in self?.showMenuFeedback(text) }
        // No alerter: a cookie-less page has no alert link, so the account's alert form is never the way here.
        let alerts = ModeratorAlertModel(
            alerter: nil, mailAddress: services.moderatorAlertMail, confirm: confirm, openMail: openMail
        )
        self.alerts = alerts
        var handlers: [any MessageActionHandler] = [LinkActionHandler(copy: copy, confirm: confirm), alerts.handler]
        if let lists {
            handlers += PseudoListActionHandler.all(
                manager: lists, confirm: confirm, rebuild: { [weak self] in self?.listsRevision += 1 },
                login: { [weak self] in self?.wantsSignIn = true }
            )
        }
        registry = MessageActionRegistry(handlers)
    }

    /// The reader's display settings, as they are now (a blocked author's posts masked), with the menu buttons the handlers
    /// can serve.
    func renderOptions() -> ReaderRenderOptions {
        var options = baseOptions()
        options.showsMessageMenus = registry.offers(.message)
        options.showsAuthorMenus = registry.offers(.avatar)
        return options
    }

    /// The document of `result`, numbered `token`. A rebuild after a list change keeps the scroll position, as the reader's
    /// `applyDisplaySettings()` does; a new batch opens at its top.
    func document(for result: FilteredPostsResult, token: Int, keepsScrollPosition: Bool) -> ReaderDocument {
        ReaderDocument(
            token: token, html: TopicHTMLBuilder.document(for: result.page, token: token, options: renderOptions()),
            anchor: nil, keepsScrollPosition: keepsScrollPosition
        )
    }

    /// The menu of message `post` of `result`, or nil when the batch does not hold it or nothing applies.
    func menu(post: Int, source: MessageMenuSource, anchor: CGRect?, in result: FilteredPostsResult) -> MessageMenu? {
        guard let message = result.page.messages.first(where: { !$0.isContinuation && $0.numreponse == post }) else { return nil }
        let context = MessageMenuContext(
            numreponse: post, author: message.author, actions: message.actions,
            permalinkURL: Self.permalink(of: post, in: result), topic: result.topic
        )
        var entries = registry.entries(for: context, source: source)
        // No edit link on a cookie-less page: the user's own post is known by its author (legacy `isOwnMessage`).
        if lists?.isOwn(message.author) ?? false { entries.removeAll { Self.othersOnly.contains($0.kind) } }
        guard !entries.isEmpty else { return nil }
        return MessageMenu(post: post, source: source, context: context, entries: entries, anchor: anchor)
    }

    /// Runs `action` of `menu`; an action the menu did not offer does nothing.
    func perform(_ action: MessageMenuAction, in menu: MessageMenu) async {
        guard menu.entries.contains(action) else { return }
        await registry.perform(action, with: menu.context)
    }

    /// Shows `text` as the confirmation of the last action.
    func showMenuFeedback(_ text: String) {
        menuFeedback = text
        menuFeedbackSerial += 1
    }

    func clearMenuFeedback(serial: Int) {
        guard serial == menuFeedbackSerial else { return }
        menuFeedback = nil
    }

    /// The entries never offered on the user's own post (legacy's policy: alert and lists are for another member).
    private static let othersOnly: Set<MessageMenuAction.Kind> = [.alert, .blocklist, .allowlist, .signInToBlock]

    /// The page the message was read on, with its `#t<numreponse>` anchor (HFR-PROTOCOL R5, `HFREndpoint.topicPage`); nil when
    /// the batch does not say which page.
    static func permalink(of post: Int, in result: FilteredPostsResult) -> URL? {
        guard let page = result.pages[post] else { return nil }
        return try? HFREndpoint.topicPage(topic: result.topic, page: page, anchor: post).url
    }
}
