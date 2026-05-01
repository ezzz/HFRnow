import XCTest
@testable import HFRswift

final class ObjCAccountSessionServiceTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        AccountSessionURLProtocolMock.requestHandler = nil
        clearHardwareCookiesFromSharedStorage()
    }

    func testFetchAccountsMapsObjCPayload() {
        let avatarData = Data([0x01, 0x02, 0x03])
        let manager = MultisManagerStub()
        manager.comptesPayload = [
            [
                "PSEUDO": "alpha",
                "PSEUDO_DISPLAY": "Alpha Display",
                "MAIN": NSNumber(value: true),
                "AVATAR": avatarData
            ],
            [
                "PSEUDO_DISPLAY": "Fallback ID",
                "MAIN": NSNumber(value: false)
            ]
        ]

        let service = ObjCAccountSessionService(multisManager: manager, loginService: LoginService())
        let accounts = service.fetchAccounts()

        XCTAssertEqual(accounts.count, 2)
        XCTAssertEqual(accounts[0].id, "alpha")
        XCTAssertEqual(accounts[0].displayName, "Alpha Display")
        XCTAssertTrue(accounts[0].isMain)
        XCTAssertEqual(accounts[0].avatarData, avatarData)
        XCTAssertEqual(accounts[1].id, "Fallback ID")
    }

    func testSetMainAccountDelegatesToMultisManager() {
        let manager = MultisManagerStub()
        manager.comptesPayload = [
            ["PSEUDO": "main-pseudo", "PSEUDO_DISPLAY": "Main Pseudo"]
        ]
        let service = ObjCAccountSessionService(multisManager: manager, loginService: LoginService())

        service.setMainAccount(id: "main-pseudo")

        XCTAssertEqual(manager.setMainPseudoCalls, ["main-pseudo"])
    }

    func testSetMainAccountResolvesPseudoFromCookiesWhenPseudoMissing() throws {
        let manager = MultisManagerStub()
        manager.comptesPayload = [
            [
                "PSEUDO_DISPLAY": "Display Name",
                "COOKIES": [try makeCookie(name: "md_user", value: "cookie-pseudo")]
            ]
        ]
        let service = ObjCAccountSessionService(multisManager: manager, loginService: LoginService())

        service.setMainAccount(id: "Display Name")

        XCTAssertEqual(manager.setMainPseudoCalls, ["cookie-pseudo"])
    }

    func testDeleteAccountDelegatesUsingMatchingIndex() {
        let manager = MultisManagerStub()
        manager.comptesPayload = [
            ["PSEUDO": "first", "PSEUDO_DISPLAY": "First"],
            ["PSEUDO": "second", "PSEUDO_DISPLAY": "Second"]
        ]
        let service = ObjCAccountSessionService(multisManager: manager, loginService: LoginService())

        service.deleteAccount(id: "second")

        XCTAssertEqual(manager.deletedIndices, [1])
    }
    
    func testSetMainAccountMatchesTrimmedAndCaseInsensitiveIdentifier() {
        let manager = MultisManagerStub()
        manager.comptesPayload = [
            ["PSEUDO": "CasePseudo", "PSEUDO_DISPLAY": "Display Name"]
        ]
        let service = ObjCAccountSessionService(multisManager: manager, loginService: LoginService())

        service.setMainAccount(id: "  casepseudo  ")

        XCTAssertEqual(manager.setMainPseudoCalls, ["CasePseudo"])
    }

    func testDeleteAccountMatchesDisplayNameCaseInsensitive() {
        let manager = MultisManagerStub()
        manager.comptesPayload = [
            ["PSEUDO": "alpha", "PSEUDO_DISPLAY": "Alpha Display"],
            ["PSEUDO": "beta", "PSEUDO_DISPLAY": "Beta Display"]
        ]
        let service = ObjCAccountSessionService(multisManager: manager, loginService: LoginService())

        service.deleteAccount(id: "  beta display ")

        XCTAssertEqual(manager.deletedIndices, [1])
    }

    func testMakeReplySessionContextCopiesCookiesForcesCookiesAndSetsHash() throws {
        let manager = MultisManagerStub()
        let cookie = try XCTUnwrap(
            HTTPCookie(properties: [
                .domain: "forum.hardware.fr",
                .path: "/",
                .name: "sessionid",
                .value: "cookie-value",
                .expires: Date(timeIntervalSinceNow: 3600)
            ])
        )
        manager.mainComptePayload = [
            "PSEUDO_DISPLAY": "Pseudo Display",
            "PSEUDO": "pseudo-key",
            "HASH": "hash-123",
            "COOKIES": [cookie]
        ]
        let service = ObjCAccountSessionService(multisManager: manager, loginService: LoginService())
        let storage = makeIsolatedCookieStorage()

        let context = try service.makeReplySessionContext(cookieStorage: storage)

        XCTAssertEqual(context.pseudoDisplay, "Pseudo Display")
        XCTAssertEqual(context.hashCheck, "hash-123")
        XCTAssertEqual(manager.forceCookiesForCompteCalls.count, 1)
        XCTAssertEqual(manager.setHashForCompteCalls.count, 1)
        XCTAssertEqual(manager.setHashForCompteCalls.first?.hash, "hash-123")
        XCTAssertTrue(storage.cookies?.contains(where: { $0.name == "sessionid" }) == true)
    }

    func testMakeReplySessionContextPreservesMultiQuoteCookiesWhenForceCookiesClearsStorage() throws {
        clearHardwareCookiesFromSharedStorage()

        let manager = MultisManagerStub()
        let sessionCookie = try makeCookie(name: "sessionid", value: "cookie-value")
        let quoteCookie = try XCTUnwrap(
            HTTPCookie(properties: [
                .domain: ".hardware.fr",
                .path: "/",
                .name: "quoteshardwarefr-prive-2763298",
                .value: "|1980613576",
                .expires: Date(timeIntervalSinceNow: 3600)
            ])
        )
        HTTPCookieStorage.shared.setCookie(quoteCookie)

        manager.mainComptePayload = [
            "PSEUDO_DISPLAY": "Pseudo Display",
            "PSEUDO": "pseudo-key",
            "HASH": "hash-123",
            "COOKIES": [sessionCookie]
        ]
        manager.forceCookiesHandler = {
            let storage = HTTPCookieStorage.shared
            for cookie in storage.cookies ?? [] {
                storage.deleteCookie(cookie)
            }
        }

        let service = ObjCAccountSessionService(multisManager: manager, loginService: LoginService())

        _ = try service.makeReplySessionContext(cookieStorage: .shared)

        let cookies = HTTPCookieStorage.shared.cookies ?? []
        XCTAssertTrue(cookies.contains(where: { $0.name == "sessionid" && $0.value == "cookie-value" }))
        XCTAssertTrue(cookies.contains(where: { $0.name == "quoteshardwarefr-prive-2763298" && $0.value == "|1980613576" }))
    }

    func testMakeReplySessionContextWithoutMainAccountThrowsNoActiveAccount() {
        let manager = MultisManagerStub()
        manager.mainComptePayload = nil
        let service = ObjCAccountSessionService(multisManager: manager, loginService: LoginService())

        do {
            _ = try service.makeReplySessionContext(cookieStorage: makeIsolatedCookieStorage())
            XCTFail("Expected noActiveAccount")
        } catch let error as ReplyPostingError {
            switch error {
            case .noActiveAccount:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testMakeReplySessionContextFallsBackToFirstCompteWhenNoMainExists() throws {
        let manager = MultisManagerStub()
        manager.mainComptePayload = nil
        manager.comptesPayload = [
            [
                "PSEUDO_DISPLAY": "Fallback Display",
                "PSEUDO": "fallback-pseudo",
                "HASH": "fallback-hash",
                "COOKIES": [try makeCookie(name: "sessionid", value: "cookie-value")]
            ]
        ]
        let service = ObjCAccountSessionService(multisManager: manager, loginService: LoginService())
        let storage = makeIsolatedCookieStorage()

        let context = try service.makeReplySessionContext(cookieStorage: storage)

        XCTAssertEqual(context.pseudoDisplay, "Fallback Display")
        XCTAssertEqual(context.hashCheck, "fallback-hash")
        XCTAssertEqual(manager.setMainPseudoCalls, ["fallback-pseudo"])
        XCTAssertEqual(manager.forceCookiesForCompteCalls.count, 1)
        XCTAssertTrue(storage.cookies?.contains(where: { $0.name == "sessionid" }) == true)
    }

    func testMakeReplySessionContextIgnoresUnusableMainPayloadAndFallsBackToUsableCompte() throws {
        let manager = MultisManagerStub()
        manager.mainComptePayload = [:]
        manager.comptesPayload = [
            [
                "PSEUDO_DISPLAY": "Fallback Display",
                "PSEUDO": "fallback-pseudo",
                "HASH": "fallback-hash",
                "COOKIES": [try makeCookie(name: "sessionid", value: "cookie-value")]
            ]
        ]
        let service = ObjCAccountSessionService(multisManager: manager, loginService: LoginService())
        let storage = makeIsolatedCookieStorage()

        let context = try service.makeReplySessionContext(cookieStorage: storage)

        XCTAssertEqual(context.pseudoDisplay, "Fallback Display")
        XCTAssertEqual(context.hashCheck, "fallback-hash")
        XCTAssertEqual(manager.setMainPseudoCalls, ["fallback-pseudo"])
        XCTAssertEqual(manager.forceCookiesForCompteCalls.count, 1)
    }

    func testMakeReplySessionContextPrefersCompteMarkedMainWhenManagerMainPayloadIsMissing() throws {
        let manager = MultisManagerStub()
        manager.mainComptePayload = nil
        manager.comptesPayload = [
            [
                "PSEUDO_DISPLAY": "Alpha",
                "PSEUDO": "alpha",
                "MAIN": NSNumber(value: false),
                "COOKIES": [try makeCookie(name: "sessionid", value: "alpha-cookie")]
            ],
            [
                "PSEUDO_DISPLAY": "Beta",
                "PSEUDO": "beta",
                "MAIN": NSNumber(value: true),
                "HASH": "beta-hash",
                "COOKIES": [try makeCookie(name: "sessionid", value: "beta-cookie")]
            ]
        ]
        let service = ObjCAccountSessionService(multisManager: manager, loginService: LoginService())

        let context = try service.makeReplySessionContext(cookieStorage: makeIsolatedCookieStorage())

        XCTAssertEqual(context.pseudoDisplay, "Beta")
        XCTAssertEqual(context.hashCheck, "beta-hash")
        XCTAssertEqual(manager.setMainPseudoCalls, ["beta"])
    }

    func testAddAccountUsesLoginServiceAndUpdatesMultisManager() async throws {
        clearHardwareCookiesFromSharedStorage()

        AccountSessionURLProtocolMock.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/login_validation.php") {
                XCTAssertEqual(request.httpMethod, "POST")
                let headers = ["Set-Cookie": "md_user=PseudoKey42; Domain=.hardware.fr; Path=/; HttpOnly"]
                let html = "<html><body>login_redirection.php</body></html>"
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: headers
                )!
                return (response, Data(html.utf8))
            }

            if path.hasSuffix("/user/editprofil.php") {
                XCTAssertEqual(request.httpMethod, "GET")
                let html = """
                <html><body>
                <input type="hidden" name="hash_check" value="hash-xyz" />
                </body></html>
                """
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data(html.utf8))
            }

            XCTFail("Unexpected request path: \(path)")
            throw URLError(.badURL)
        }

        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.protocolClasses = [AccountSessionURLProtocolMock.self]

        let manager = MultisManagerStub()
        let loginService = LoginService(session: URLSession(configuration: config))
        let service = ObjCAccountSessionService(multisManager: manager, loginService: loginService)

        try await service.addAccount(pseudo: "  Tester  ", password: "Secret")

        XCTAssertEqual(manager.addCompteCalls.count, 1)
        XCTAssertEqual(manager.addCompteCalls.first?.pseudo, "Tester")
        XCTAssertEqual(manager.addCompteCalls.first?.hash, "hash-xyz")
        XCTAssertEqual(manager.setMainPseudoCalls, ["PseudoKey42"])
        XCTAssertTrue(manager.addCompteCalls.first?.cookies.contains(where: { $0.name == "md_user" && $0.value == "PseudoKey42" }) == true)
    }
    
    func testAddAccountRejectsBlankPseudoBeforeNetwork() async {
        let manager = MultisManagerStub()
        let service = ObjCAccountSessionService(multisManager: manager, loginService: LoginService())

        do {
            try await service.addAccount(pseudo: "   ", password: "Secret")
            XCTFail("Expected invalidPseudo error")
        } catch let error as AccountSessionError {
            switch error {
            case .invalidPseudo:
                break
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeIsolatedCookieStorage() -> HTTPCookieStorage {
        let config = URLSessionConfiguration.ephemeral
        return config.httpCookieStorage ?? .shared
    }

    private func makeCookie(name: String, value: String) throws -> HTTPCookie {
        try XCTUnwrap(
            HTTPCookie(properties: [
                .domain: "forum.hardware.fr",
                .path: "/",
                .name: name,
                .value: value,
                .expires: Date(timeIntervalSinceNow: 3600)
            ])
        )
    }

    private func clearHardwareCookiesFromSharedStorage() {
        let storage = HTTPCookieStorage.shared
        let matching = (storage.cookies ?? []).filter { $0.domain.contains("hardware.fr") }
        for cookie in matching {
            storage.deleteCookie(cookie)
        }
    }
}

private final class MultisManagerStub: LegacyAccountsManaging {
    var comptesPayload: [[String: Any]] = []
    var mainComptePayload: [AnyHashable: Any]?
    var setMainPseudoCalls: [String] = []
    var deletedIndices: [Int] = []
    var addCompteCalls: [(pseudo: String, cookies: [HTTPCookie], avatar: Data?, hash: String?)] = []
    var forceCookiesForCompteCalls: [[AnyHashable: Any]] = []
    var forceCookiesHandler: (() -> Void)?
    var setHashForCompteCalls: [(compte: [AnyHashable: Any], hash: String)] = []

    func comptes() -> [LegacyRawCompte] {
        comptesPayload
    }

    func mainCompte() -> LegacyRawCompte? {
        mainComptePayload
    }

    func currentPseudo() -> String? {
        (mainComptePayload?["PSEUDO_DISPLAY"] as? String) ?? (mainComptePayload?["PSEUDO"] as? String)
    }

    func currentAccountIdentity() -> LegacyAccountIdentity? {
        guard let pseudo = currentPseudo()?.trimmingCharacters(in: .whitespacesAndNewlines), !pseudo.isEmpty else {
            return nil
        }
        let rawDisplayName = (mainComptePayload?["PSEUDO_DISPLAY"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = rawDisplayName?.isEmpty == false ? rawDisplayName ?? pseudo : pseudo
        return LegacyAccountIdentity(pseudo: pseudo, displayName: displayName)
    }

    func setMainPseudo(_ pseudo: String) {
        setMainPseudoCalls.append(pseudo)
    }

    func deletePseudo(at index: Int) {
        deletedIndices.append(index)
    }

    func addCompte(pseudo: String, cookies: [HTTPCookie], avatar: Data?, hash: String?) {
        addCompteCalls.append((pseudo: pseudo, cookies: cookies, avatar: avatar, hash: hash))
    }

    func forceCookies(for compte: LegacyRawCompte) {
        forceCookiesForCompteCalls.append(compte)
        forceCookiesHandler?()
    }

    func setHash(_ hash: String, for compte: LegacyRawCompte) {
        setHashForCompteCalls.append((compte: compte, hash: hash))
    }
}

private final class AccountSessionURLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
