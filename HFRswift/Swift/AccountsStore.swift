//
//  AccountsStore.swift
//  HFRswift
//
//  Created by Bruno ARENE on 29/01/2026.
//

import Combine
import Foundation
import UIKit

struct Account: Identifiable, Equatable {
    let id: String
    let displayName: String
    let isMain: Bool
    let avatarData: Data?

    var avatarImage: UIImage? {
        guard let avatarData else { return nil }
        return UIImage(data: avatarData)
    }

    static func == (lhs: Account, rhs: Account) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class AccountsStore: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var currentAccount: Account?

    private let multisManager: MultisManager
    private let loginService: LoginService
    private var notificationCancellable: AnyCancellable?

    init(
        multisManager: MultisManager = MultisManager.sharedManager() as! MultisManager,
        loginService: LoginService = LoginService()
    ) {
        self.multisManager = multisManager
        self.loginService = loginService
        refresh()

        notificationCancellable = NotificationCenter.default
            .publisher(for: Notification.Name("kLoginChangedNotification"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    func refresh() {
        let rawAccounts = multisManager.getComtpes() as? [[String: Any]] ?? []
        let mapped = rawAccounts.compactMap { dict -> Account? in
            let pseudoKey = dict[AccountKeys.pseudo] as? String
            let id = pseudoKey ?? dict[AccountKeys.pseudoDisplay] as? String
            guard let id else { return nil }
            let displayName = dict[AccountKeys.pseudoDisplay] as? String ?? id
            let isMain = (dict[AccountKeys.main] as? NSNumber)?.boolValue ?? false
            let avatarData = dict[AccountKeys.avatar] as? Data
            return Account(id: id, displayName: displayName, isMain: isMain, avatarData: avatarData)
        }
        accounts = mapped
        currentAccount = mapped.first(where: { $0.isMain }) ?? mapped.first
    }

    func setMain(_ account: Account) {
        multisManager.setPseudo(asMain: account.id)
        refresh()
    }

    func delete(_ account: Account) {
        guard let index = accounts.firstIndex(of: account) else { return }
        multisManager.deletePseudo(at: index)
        refresh()
    }

    func deleteCurrent() {
        guard let currentAccount else { return }
        delete(currentAccount)
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
        refresh()
    }

    var currentAvatarImage: UIImage? {
        currentAccount?.avatarImage
    }
}

private enum AccountKeys {
    static let pseudo = "PSEUDO"
    static let pseudoDisplay = "PSEUDO_DISPLAY"
    static let avatar = "AVATAR"
    static let main = "MAIN"
}
