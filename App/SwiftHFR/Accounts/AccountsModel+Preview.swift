import Foundation
import HFRClient
import HFRNetwork
import HFRStorage

extension AccountsModel {
    /// A model for SwiftUI previews: in-memory store, no account, and logins that never reach the forum.
    static func preview() -> AccountsModel {
        AccountsModel(
            store: InMemoryCredentialStore(),
            loginService: OfflineLogin(),
            checker: NoSessionCheck(),
            avatars: NoAvatars()
        )
    }
}

/// Fails every login as offline, so a preview never contacts the forum.
private struct OfflineLogin: AccountLoggingIn {
    func logIn(
        pseudo: String, password: String, into session: HFRSession, expectedUserKey: String?
    ) async throws(LoginError) -> LoginResult {
        throw .network(.offline)
    }
}

/// Confirms nothing and sends nothing, so a preview never contacts the forum.
private struct NoSessionCheck: SessionChecking {
    func check(_ session: HFRSession) async -> SessionCheckResult { .unconfirmed }
}

/// Never downloads anything.
private struct NoAvatars: AvatarLoading {
    func avatarData(at url: URL) async -> Data? { nil }
}
