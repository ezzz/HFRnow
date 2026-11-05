import Foundation
import HFRModels

/// The menu of one message, presented to the user.
struct MessageMenu: Equatable, Identifiable, Sendable {
    /// Message number.
    let post: Int
    /// Where the menu was opened.
    let source: MessageMenuSource
    /// What the context says, kept so the picked action runs on what the user saw.
    let context: MessageMenuContext
    /// The entries to show, in menu order; never empty.
    let entries: [MessageMenuAction]

    var id: String { "\(source.rawValue)-\(post)" }
}

// Port of HFRswift/Swift/MessagesView.swift (the message popup: `presentPopupMenu`, entries per action) and of
// Classes/ObjCMessageActionsBuilder.m:91-104 (`permalinkURLForPostID`) @ 2440d79. Differences: GAP-064, spec differences 1-5.
/// The message menu of the reader (LOT-087): what a tap on the web view's button opens and what picking an entry runs.
/// Its state lives on `TopicReaderModel` (`presentedMenu`, `registry`, `menuFeedback`); it is internal rather than
/// `private(set)` only so this file can hold the logic (the model file is at its length limit): by convention these methods
/// are the only writers.
extension TopicReaderModel {
    /// Plugs the handlers of the merged lots into the message menu (LOT-087); none leaves the reader without menu.
    func install(_ registry: MessageActionRegistry) {
        self.registry = registry
    }

    /// Whether the document draws the `⋯` button: an action of the message menu is implemented.
    var hasMessageMenus: Bool { registry.offers(.message) }

    /// Whether the document makes authors tappable: an action of the author menu is implemented.
    var hasAuthorMenus: Bool { registry.offers(.avatar) }

    /// What the menu policy reads about message `post` of the page on screen; nil when the page does not hold it.
    func menuContext(post: Int) -> MessageMenuContext? {
        guard let page, let index = page.messages.firstIndex(where: { !$0.isContinuation && $0.numreponse == post })
        else { return nil }
        let message = page.messages[index]
        // The first message of a topic is the first block of page 1 (a continuation copy opens the later pages). Legacy hid
        // the deletion on the first message of every page (`messageIndex != 0`): see the spec, difference 4.
        let isFirst = page.currentPage == 1 && !page.messages[..<index].contains { !$0.isContinuation }
        return MessageMenuContext(
            numreponse: post, author: message.author, actions: message.actions,
            permalinkURL: Self.permalink(of: post, on: page), isFirstPostOfTopic: isFirst
        )
    }

    /// The page's URL without fragment plus `#t<numreponse>` (legacy `permalinkURLForPostID`, anchors of HFR-PROTOCOL §6c).
    static func permalink(of post: Int, on page: ReaderPage) -> URL? {
        guard let base = page.pageURL, var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        components.fragment = "t\(post)"
        return components.url
    }

    /// The web view reports a tap on a message's menu button or author. A menu is shown only for a message of the document
    /// on screen and only when it has entries, so a late or forged request opens nothing.
    func requestMenu(post: Int, source: MessageMenuSource, token: Int) {
        guard token == document?.token, let context = menuContext(post: post) else { return }
        let entries = registry.entries(for: context, source: source)
        // A request that offers nothing leaves an open menu alone, like a refused one (the popover keeps the page tappable).
        guard !entries.isEmpty else { return }
        presentedMenu = MessageMenu(post: post, source: source, context: context, entries: entries)
    }

    /// Closes the menu without choosing.
    func dismissMenu() {
        presentedMenu = nil
    }

    /// Runs `action` of `menu` through its handler and closes the menu. The menu comes from the caller because the dialog
    /// closes (and clears `presentedMenu`) before the action runs; an action the menu did not offer does nothing.
    func perform(_ action: MessageMenuAction, in menu: MessageMenu) async {
        presentedMenu = nil
        guard menu.entries.contains(action) else { return }
        await registry.perform(action, with: menu.context)
    }

    /// Shows `text` as the confirmation of the last action.
    func showMenuFeedback(_ text: String) {
        menuFeedback = text
        menuFeedbackSerial += 1
    }

    /// Hides the confirmation `serial` stands for; a newer confirmation (same text, later serial) stays on screen.
    func clearMenuFeedback(serial: Int) {
        guard serial == menuFeedbackSerial else { return }
        menuFeedback = nil
    }
}
