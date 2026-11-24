import SwiftUI

// Port of HFRswift/Swift/MessagesView.swift (the author menu's `.blacklist` entry, `:213-216`; toggleAvatarBlacklist /
// toggleProfileBlacklist `:4470-4484`) @ 87fe0d1c. Differences: GAP-1297, LOT-159 D3 (operator, 2026-11-24, #1297): legacy offers
// Blacklist with no account check and, logged out, reports success while keeping nothing (`BlackList.m:37-47` adds to the throwaway
// array `getBlackListForActiveCompte` returns when there is no current pseudo, `:92-94`); here « Connectez-vous pour bloquer »
// takes its place and opens the login.
/// The words of the logged-out stand-in for the blocklist entries.
enum SignInToBlock {
    static let title = "Connectez-vous pour bloquer"
    /// VoiceOver hint of the entry where a screen draws it as a button (the profile sheet).
    static let hint = "Ouvre la connexion. La liste noire est liée à un compte."
}

/// « Connectez-vous pour bloquer » in the author menu: offered while no account is logged in, in place of « Blacklist » (the
/// blocklist is per account, LOT-118), and opens the login.
@MainActor
struct SignInToBlockActionHandler: MessageActionHandler {
    let manager: PseudoListManager
    /// Opens the login of the screen the menu belongs to.
    let openLogin: @MainActor () -> Void

    var kind: MessageMenuAction.Kind { .signInToBlock }

    func isAvailable(for context: MessageMenuContext) -> Bool { !manager.isAvailable(.blocklist) }

    func perform(with context: MessageMenuContext) async { openLogin() }
}

extension PseudoListActionHandler {
    /// Blacklist and Whitelist, plus the logged-out stand-in for the blocklist (LOT-159 D3): the one list of handlers every
    /// author menu registers.
    static func all(
        manager: PseudoListManager, confirm: @escaping @MainActor (String) -> Void, rebuild: @escaping @MainActor () -> Void,
        login: @escaping @MainActor () -> Void
    ) -> [any MessageActionHandler] {
        pair(manager: manager, confirm: confirm, rebuild: rebuild) + [SignInToBlockActionHandler(manager: manager, openLogin: login)]
    }
}

extension TopicReaderModel {
    /// The list handlers of the reader's author menu: Blacklist, Whitelist and, logged out, « Connectez-vous pour bloquer », which
    /// asks the reader for the login (`asksLogin`). One place the view calls, so a test can see what the reader registers.
    func pseudoListHandlers(
        lists: PseudoListManager?, confirm: @escaping @MainActor (String) -> Void, rebuild: @escaping @MainActor () -> Void
    ) -> [any MessageActionHandler] {
        guard let lists else { return [] }
        return PseudoListActionHandler.all(
            manager: lists, confirm: confirm, rebuild: rebuild, login: { [weak self] in self?.asksLogin = true }
        )
    }
}

private struct SignInToBlockSheet: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(AccountsModel.self) private var accounts

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) { LoginView(target: .newAccount, accounts: accounts) }
    }
}

extension View {
    /// The login sheet opened by « Connectez-vous pour bloquer ».
    func signInToBlockSheet(isPresented: Binding<Bool>) -> some View {
        modifier(SignInToBlockSheet(isPresented: isPresented))
    }
}
