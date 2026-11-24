import SwiftUI

// No legacy counterpart: legacy offers Blacklist to an account only (`MessagesView.swift:1683-1717` @ 2440d79) and says nothing
// when logged out. Differences: GAP-1297, LOT-159 D3 (operator, 2026-11-24, #1297).
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
        openLogin: @escaping @MainActor () -> Void
    ) -> [any MessageActionHandler] {
        pair(manager: manager, confirm: confirm, rebuild: rebuild) + [SignInToBlockActionHandler(manager: manager, openLogin: openLogin)]
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
