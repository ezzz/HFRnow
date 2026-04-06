import Foundation
import UIKit

enum AccountSessionError: LocalizedError {
    case invalidPseudo

    var errorDescription: String? {
        switch self {
        case .invalidPseudo:
            return "Pseudo invalide."
        }
    }
}

protocol AccountSessionService {
    func fetchAccounts() -> [Account]
    func setMainAccount(id: String)
    func deleteAccount(id: String)
    func addAccount(pseudo: String, password: String) async throws
    func makeReplySessionContext(cookieStorage: HTTPCookieStorage) throws -> ReplySessionContext
}

final class ObjCAccountSessionService: AccountSessionService {
    private typealias RawCompte = LegacyRawCompte

    private let multisManager: LegacyAccountsManaging
    private let loginService: LoginService

    init(
        multisManager: LegacyAccountsManaging = ObjCLegacyAccountsManager.shared,
        loginService: LoginService = LoginService()
    ) {
        self.multisManager = multisManager
        self.loginService = loginService
    }

    func fetchAccounts() -> [Account] {
        rawComptes().compactMap { compte in
            let pseudoKey = pseudoKey(from: compte)
            let displayName = displayName(from: compte, fallbackPseudo: pseudoKey)
            let id = pseudoKey ?? displayName
            guard !id.isEmpty else { return nil }
            let isMain = (compte[AccountKeys.main] as? NSNumber)?.boolValue ?? false
            let avatarData = compte[AccountKeys.avatar] as? Data
            return Account(id: id, displayName: displayName, isMain: isMain, avatarData: avatarData)
        }
    }

    func setMainAccount(id: String) {
        guard let accountIndex = resolveCompteIndex(forIdentifier: id) else { return }
        let compte = rawComptes()[accountIndex]
        guard let pseudoKey = pseudoKey(from: compte) else { return }
        multisManager.setMainPseudo(pseudoKey)
    }

    func deleteAccount(id: String) {
        guard let accountIndex = resolveCompteIndex(forIdentifier: id) else { return }
        multisManager.deletePseudo(at: accountIndex)
    }

    func addAccount(pseudo: String, password: String) async throws {
        let trimmedPseudo = pseudo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPseudo.isEmpty else {
            throw AccountSessionError.invalidPseudo
        }

        let result = try await loginService.login(pseudo: trimmedPseudo, password: password)
        multisManager.addCompte(
            pseudo: trimmedPseudo,
            cookies: result.cookies,
            avatar: result.avatarData,
            hash: result.hash
        )
        multisManager.setMainPseudo(result.pseudoKey)
    }

    func makeReplySessionContext(cookieStorage: HTTPCookieStorage) throws -> ReplySessionContext {
        guard let mainCompte = resolveMainCompte() else {
            throw ReplyPostingError.noActiveAccount
        }

        let preservedReplyCookies = preservedReplyCookies(in: cookieStorage)
        multisManager.forceCookies(for: mainCompte)
        restorePreservedReplyCookies(preservedReplyCookies, into: cookieStorage)

        if let cookies = mainCompte[AccountKeys.cookies] as? [HTTPCookie] {
            for cookie in cookies {
                cookieStorage.setCookie(cookie)
            }
        }

        let pseudoDisplay = nonEmptyString(mainCompte[AccountKeys.pseudoDisplay]) ?? nonEmptyString(mainCompte[AccountKeys.pseudo])
        var hashCheck = nonEmptyString(mainCompte[AccountKeys.hash])

        if hashCheck == nil,
           let appDelegate = HFRplusAppDelegate.shared() as? HFRplusAppDelegate {
            hashCheck = nonEmptyString(appDelegate.hash_check)
        }

        if let hashCheck {
            multisManager.setHash(hashCheck, for: mainCompte)
        }

        return ReplySessionContext(pseudoDisplay: pseudoDisplay, hashCheck: hashCheck)
    }

    private func preservedReplyCookies(in cookieStorage: HTTPCookieStorage) -> [HTTPCookie] {
        (cookieStorage.cookies ?? []).filter { $0.name.hasPrefix("quotes") }
    }

    private func restorePreservedReplyCookies(_ cookies: [HTTPCookie], into cookieStorage: HTTPCookieStorage) {
        for cookie in cookies {
            cookieStorage.setCookie(cookie)
        }
    }

    private func rawComptes() -> [RawCompte] {
        multisManager.comptes()
    }

    private func pseudoKey(from compte: RawCompte) -> String? {
        if let pseudo = nonEmptyString(compte[AccountKeys.pseudo]) {
            return pseudo
        }

        guard let cookies = compte[AccountKeys.cookies] as? [HTTPCookie] else {
            return nil
        }

        return cookies.first(where: { $0.name == "md_user" && $0.value != "deleted" })?.value
    }

    private func displayName(from compte: RawCompte, fallbackPseudo: String?) -> String {
        nonEmptyString(compte[AccountKeys.pseudoDisplay]) ?? fallbackPseudo ?? ""
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedIdentifier(_ value: String?) -> String? {
        guard let nonEmpty = nonEmptyString(value) else { return nil }
        return nonEmpty.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func resolveCompteIndex(forIdentifier id: String) -> Int? {
        let comptes = rawComptes()
        guard let normalizedID = normalizedIdentifier(id) else { return nil }

        if let pseudoIndex = comptes.firstIndex(where: { normalizedIdentifier(nonEmptyString($0[AccountKeys.pseudo])) == normalizedID }) {
            return pseudoIndex
        }

        if let displayIndex = comptes.firstIndex(where: { normalizedIdentifier(nonEmptyString($0[AccountKeys.pseudoDisplay])) == normalizedID }) {
            return displayIndex
        }

        return comptes.firstIndex { compte in
            normalizedIdentifier(pseudoKey(from: compte)) == normalizedID
        }
    }

    private func resolveMainCompte() -> RawCompte? {
        if let mainCompte = multisManager.mainCompte(),
           isUsableCompte(mainCompte) {
            return mainCompte
        }

        let comptes = rawComptes()
        let fallbackCompte =
            comptes.first(where: { (($0[AccountKeys.main] as? NSNumber)?.boolValue ?? false) && isUsableCompte($0) }) ??
            comptes.first(where: isUsableCompte)

        guard let fallbackCompte else {
            return nil
        }

        if let fallbackPseudo = pseudoKey(from: fallbackCompte) {
            multisManager.setMainPseudo(fallbackPseudo)
        }

        return fallbackCompte
    }

    private func isUsableCompte(_ compte: RawCompte) -> Bool {
        pseudoKey(from: compte) != nil || nonEmptyString(compte[AccountKeys.pseudoDisplay]) != nil
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
