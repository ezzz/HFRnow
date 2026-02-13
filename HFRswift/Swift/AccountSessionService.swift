import Foundation
import UIKit

protocol AccountSessionService {
    func fetchAccounts() -> [Account]
    func setMainAccount(id: String)
    func deleteAccount(id: String)
    func addAccount(pseudo: String, password: String) async throws
    func makeReplySessionContext(cookieStorage: HTTPCookieStorage) throws -> ReplySessionContext
}

final class ObjCAccountSessionService: AccountSessionService {
    private let multisManager: MultisManager
    private let loginService: LoginService

    init(
        multisManager: MultisManager = MultisManager.sharedManager() as! MultisManager,
        loginService: LoginService = LoginService()
    ) {
        self.multisManager = multisManager
        self.loginService = loginService
    }

    func fetchAccounts() -> [Account] {
        let rawAccounts = multisManager.getComtpes() as? [[String: Any]] ?? []
        return rawAccounts.compactMap { dict in
            let pseudoKey = dict[AccountKeys.pseudo] as? String
            let id = pseudoKey ?? dict[AccountKeys.pseudoDisplay] as? String
            guard let id else { return nil }
            let displayName = dict[AccountKeys.pseudoDisplay] as? String ?? id
            let isMain = (dict[AccountKeys.main] as? NSNumber)?.boolValue ?? false
            let avatarData = dict[AccountKeys.avatar] as? Data
            return Account(id: id, displayName: displayName, isMain: isMain, avatarData: avatarData)
        }
    }

    func setMainAccount(id: String) {
        multisManager.setPseudo(asMain: id)
    }

    func deleteAccount(id: String) {
        let accounts = fetchAccounts()
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        multisManager.deletePseudo(at: index)
    }

    func addAccount(pseudo: String, password: String) async throws {
        let result = try await loginService.login(pseudo: pseudo, password: password)
        multisManager.addCompte(
            pseudo: result.displayPseudo,
            cookies: result.cookies,
            avatar: result.avatarData,
            hash: result.hash
        )
        multisManager.setPseudo(asMain: result.pseudoKey)
    }

    func makeReplySessionContext(cookieStorage: HTTPCookieStorage) throws -> ReplySessionContext {
        guard let mainCompte = multisManager.getMainCompte() as? [AnyHashable: Any] else {
            throw ReplyPostingError.noActiveAccount
        }

        multisManager.forceCookies(forCompte: mainCompte)

        if let cookies = mainCompte[AccountKeys.cookies] as? [HTTPCookie] {
            for cookie in cookies {
                cookieStorage.setCookie(cookie)
            }
        }

        let pseudoDisplay = (mainCompte[AccountKeys.pseudoDisplay] as? String) ?? (mainCompte[AccountKeys.pseudo] as? String)
        var hashCheck = mainCompte[AccountKeys.hash] as? String

        if hashCheck == nil,
           let appDelegate = HFRplusAppDelegate.shared() as? HFRplusAppDelegate {
            hashCheck = appDelegate.hash_check
        }

        if let hashCheck {
            multisManager.setHashForCompte(mainCompte, andHash: hashCheck)
        }

        return ReplySessionContext(pseudoDisplay: pseudoDisplay, hashCheck: hashCheck)
    }
}

private enum AccountKeys {
    static let pseudo = "PSEUDO"
    static let pseudoDisplay = "PSEUDO_DISPLAY"
    static let avatar = "AVATAR"
    static let main = "MAIN"
    static let hash = "HASH"
    static let cookies = "COOKIES"
}
