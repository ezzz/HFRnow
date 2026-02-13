import XCTest
@testable import HFRswift

@MainActor
final class AccountsStoreTests: XCTestCase {
    func testRefreshLoadsAccountsFromService() {
        let mockService = MockAccountSessionService()
        mockService.accounts = [
            Account(id: "alpha", displayName: "Alpha", isMain: false, avatarData: nil),
            Account(id: "beta", displayName: "Beta", isMain: true, avatarData: nil)
        ]

        let store = AccountsStore(accountSessionService: mockService)

        XCTAssertEqual(store.accounts.count, 2)
        XCTAssertEqual(store.currentAccount?.id, "beta")
        XCTAssertEqual(mockService.fetchAccountsCallCount, 1)
    }

    func testSetMainDelegatesToServiceAndRefreshes() {
        let mockService = MockAccountSessionService()
        mockService.accounts = [
            Account(id: "alpha", displayName: "Alpha", isMain: true, avatarData: nil),
            Account(id: "beta", displayName: "Beta", isMain: false, avatarData: nil)
        ]

        let store = AccountsStore(accountSessionService: mockService)
        let beta = mockService.accounts[1]

        store.setMain(beta)

        XCTAssertEqual(mockService.setMainAccountCalls, ["beta"])
        XCTAssertGreaterThanOrEqual(mockService.fetchAccountsCallCount, 2)
    }

    func testDeleteCurrentDelegatesToService() {
        let mockService = MockAccountSessionService()
        mockService.accounts = [
            Account(id: "alpha", displayName: "Alpha", isMain: true, avatarData: nil)
        ]

        let store = AccountsStore(accountSessionService: mockService)
        store.deleteCurrent()

        XCTAssertEqual(mockService.deleteAccountCalls, ["alpha"])
    }

    func testAddAccountDelegatesToServiceAndRefreshes() async throws {
        let mockService = MockAccountSessionService()
        mockService.accounts = [
            Account(id: "alpha", displayName: "Alpha", isMain: true, avatarData: nil)
        ]

        let store = AccountsStore(accountSessionService: mockService)
        try await store.addAccount(pseudo: "newbie", password: "secret")

        XCTAssertEqual(mockService.addAccountCalls.count, 1)
        XCTAssertEqual(mockService.addAccountCalls.first?.pseudo, "newbie")
        XCTAssertEqual(mockService.addAccountCalls.first?.password, "secret")
        XCTAssertGreaterThanOrEqual(mockService.fetchAccountsCallCount, 2)
    }
}

private final class MockAccountSessionService: AccountSessionService {
    var accounts: [Account] = []
    var fetchAccountsCallCount = 0
    var setMainAccountCalls: [String] = []
    var deleteAccountCalls: [String] = []
    var addAccountCalls: [(pseudo: String, password: String)] = []

    func fetchAccounts() -> [Account] {
        fetchAccountsCallCount += 1
        return accounts
    }

    func setMainAccount(id: String) {
        setMainAccountCalls.append(id)
    }

    func deleteAccount(id: String) {
        deleteAccountCalls.append(id)
    }

    func addAccount(pseudo: String, password: String) async throws {
        addAccountCalls.append((pseudo, password))
    }

    func makeReplySessionContext(cookieStorage: HTTPCookieStorage) throws -> ReplySessionContext {
        ReplySessionContext(pseudoDisplay: "mock", hashCheck: "mock-hash")
    }
}
