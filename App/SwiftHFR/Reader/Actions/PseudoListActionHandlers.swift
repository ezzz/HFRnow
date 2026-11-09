import Foundation

// Port of HFRswift/Swift/MessagesView.swift (the `.blacklist` and `.whitelist` entries, `:1683-1717`; toggleAvatarBlacklist /
// toggleAvatarWhitelist, `:3652-3694`) @ 2440d79. Differences: GAP-064; the entry toggles the author's pseudo in the store
// (LOT-117) and the page on screen is rebuilt from the refreshed snapshot, without the request legacy's `loadPage` made.
/// "Blacklist" / "Whitelist" in the message menu and the author menu (LOT-118): adds the author to the list, or removes them when
/// they are already in it, and tells the user in legacy's words. The blocklist is offered to an account only.
@MainActor
struct PseudoListActionHandler: MessageActionHandler {
    let listKind: PseudoListKind
    let manager: PseudoListManager
    /// Tells the user what changed.
    let confirm: @MainActor (String) -> Void
    /// Rebuilds the page on screen with the lists as they are now (`TopicReaderModel.applyDisplaySettings()`).
    let rebuild: @MainActor () -> Void

    var kind: MessageMenuAction.Kind { listKind == .blocklist ? .blocklist : .allowlist }

    func isAvailable(for context: MessageMenuContext) -> Bool { manager.isAvailable(listKind) }

    func perform(with context: MessageMenuContext) async {
        guard let result = await manager.toggle(context.author, in: listKind) else { return }
        confirm(result.message)
        if result.changed { rebuild() }
    }
}

extension PseudoListActionHandler {
    /// The two handlers, blocklist then allowlist.
    static func pair(
        manager: PseudoListManager, confirm: @escaping @MainActor (String) -> Void, rebuild: @escaping @MainActor () -> Void
    ) -> [PseudoListActionHandler] {
        [PseudoListKind.blocklist, .allowlist].map {
            PseudoListActionHandler(listKind: $0, manager: manager, confirm: confirm, rebuild: rebuild)
        }
    }
}
