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

    private let accountSessionService: AccountSessionService
    private var notificationCancellable: AnyCancellable?

    init(
        accountSessionService: AccountSessionService? = nil
    ) {
        self.accountSessionService = accountSessionService ?? ObjCAccountSessionService()
        refresh()

        notificationCancellable = NotificationCenter.default
            .publisher(for: Notification.Name("kLoginChangedNotification"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    func refresh() {
        let previousCurrentAccountID = currentAccount?.id
        let fetchedAccounts = accountSessionService.fetchAccounts()
        accounts = fetchedAccounts
        currentAccount =
            fetchedAccounts.first(where: { $0.isMain }) ??
            fetchedAccounts.first(where: { $0.id == previousCurrentAccountID }) ??
            fetchedAccounts.first
    }

    func setMain(_ account: Account) {
        if currentAccount?.id == account.id, currentAccount?.isMain == true {
            return
        }
        accountSessionService.setMainAccount(id: account.id)
        refresh()
    }

    func delete(_ account: Account) {
        accountSessionService.deleteAccount(id: account.id)
        refresh()
    }

    func deleteCurrent() {
        guard let currentAccount else { return }
        delete(currentAccount)
    }

    func addAccount(pseudo: String, password: String) async throws {
        try await accountSessionService.addAccount(pseudo: pseudo, password: password)
        refresh()
    }

    var currentAvatarImage: UIImage? {
        currentAccount?.avatarImage
    }
}
