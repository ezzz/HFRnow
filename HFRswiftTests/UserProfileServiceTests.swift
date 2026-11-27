import XCTest
@testable import HFRswift

/// Profile loading with the main account's session (#1349: the forum answers 403 to anonymous profile requests).
final class UserProfileServiceTests: XCTestCase {
    private let profileURL = URL(string: "https://forum.hardware.fr/hfr/profil-802171.htm")!

    override func tearDown() {
        super.tearDown()
        ProfileURLProtocolStub.requestHandler = nil
        ProfileURLProtocolStub.handledRequests = []
    }

    // MARK: - Service

    func testFetchSendsSessionCookiesAndParsesProfile() async throws {
        ProfileURLProtocolStub.requestHandler = { request in
            (Self.response(for: request, statusCode: 200), Data(Self.profileHTML.utf8))
        }
        let service = UserProfileService(
            session: makeSession(),
            sessionProvider: SessionProviderStub(cookies: [
                Self.cookie("md_user", "testeur"),
                Self.cookie("md_passs", "secret")
            ])
        )

        let profile = try await service.fetchProfile(url: profileURL)

        XCTAssertEqual(profile.pseudo, "testeur")
        let request = try XCTUnwrap(ProfileURLProtocolStub.handledRequests.first)
        let cookieHeader = try XCTUnwrap(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertTrue(cookieHeader.contains("md_user=testeur"))
        XCTAssertTrue(cookieHeader.contains("md_passs=secret"))
        XCTAssertFalse(request.httpShouldHandleCookies)
    }

    func testFetchWithoutAccountSendsNoRequest() async {
        ProfileURLProtocolStub.requestHandler = { _ in
            XCTFail("No request should be sent without a logged-in account")
            throw URLError(.badServerResponse)
        }
        let service = UserProfileService(session: makeSession(), sessionProvider: SessionProviderStub(cookies: nil))

        await assertFetch(service, throws: .loginRequired)
        XCTAssertTrue(ProfileURLProtocolStub.handledRequests.isEmpty)
    }

    func testForbiddenResponseWithFullSessionIsReportedAsAccessDenied() async {
        ProfileURLProtocolStub.requestHandler = { request in
            (Self.response(for: request, statusCode: 403), Data(Self.forbiddenHTML.utf8))
        }
        let service = UserProfileService(
            session: makeSession(),
            sessionProvider: SessionProviderStub(cookies: [
                Self.cookie("md_user", "testeur"),
                Self.cookie("md_id", "12345")
            ])
        )

        await assertFetch(service, throws: .accessDenied)
    }

    func testForbiddenResponseWithoutMemberIDAsksToLogInAgain() async {
        ProfileURLProtocolStub.requestHandler = { request in
            (Self.response(for: request, statusCode: 403), Data(Self.forbiddenHTML.utf8))
        }
        let service = UserProfileService(
            session: makeSession(),
            sessionProvider: SessionProviderStub(cookies: [Self.cookie("md_user", "testeur")])
        )

        await assertFetch(service, throws: .reloginRequired)
    }

    func testServerErrorIsReportedWithItsStatus() async {
        ProfileURLProtocolStub.requestHandler = { request in
            (Self.response(for: request, statusCode: 503), Data())
        }
        let service = UserProfileService(
            session: makeSession(),
            sessionProvider: SessionProviderStub(cookies: [Self.cookie("md_user", "testeur")])
        )

        await assertFetch(service, throws: .httpStatus(503))
    }

    // MARK: - Session provider

    func testProviderUsesMainAccountCookies() {
        let accounts = AccountsManagerStub(main: ["PSEUDO": "testeur", "MAIN": NSNumber(value: true), "COOKIES": [
            Self.cookie("md_user", "testeur"),
            Self.cookie("md_passs", "secret"),
            Self.cookie("other", "x", domain: "example.com")
        ]])
        let provider = LegacyAccountProfileSessionProvider(accountsManager: accounts, storedCookies: { _ in [] })

        let names = provider.sessionCookies(for: profileURL)?.map(\.name).sorted()

        XCTAssertEqual(names, ["md_passs", "md_user"])
    }

    func testProviderAddsStoredCookiesTheAccountDoesNotHold() {
        let accounts = AccountsManagerStub(main: ["PSEUDO": "testeur", "MAIN": NSNumber(value: true), "COOKIES": [
            Self.cookie("md_user", "testeur"),
            Self.cookie("md_passs", "secret")
        ]])
        let provider = LegacyAccountProfileSessionProvider(
            accountsManager: accounts,
            storedCookies: { _ in
                [Self.cookie("md_user", "autre"), Self.cookie("md_id", "12345"), Self.cookie("p", "1")]
            }
        )

        let cookies = provider.sessionCookies(for: profileURL) ?? []

        XCTAssertEqual(cookies.map(\.name).sorted(), ["md_id", "md_passs", "md_user", "p"])
        XCTAssertEqual(cookies.first { $0.name == "md_user" }?.value, "testeur", "the account's identity wins")
    }

    func testProviderFallsBackToSharedStorageWhenAccountHasNoCookie() {
        let provider = LegacyAccountProfileSessionProvider(
            accountsManager: AccountsManagerStub(main: nil),
            storedCookies: { _ in [Self.cookie("md_user", "testeur")] }
        )

        XCTAssertEqual(provider.sessionCookies(for: profileURL)?.map(\.name), ["md_user"])
    }

    func testProviderReportsNoSessionForLoggedOutOrExpiredCookies() {
        let now = Date.now
        let expired = Self.cookie("md_user", "testeur", expires: now.addingTimeInterval(-60))

        let usable = { (cookies: [HTTPCookie]) in
            LegacyAccountProfileSessionProvider.usableSessionCookies(cookies, for: self.profileURL, at: now)
        }

        XCTAssertNil(usable([expired]))
        XCTAssertNil(usable([Self.cookie("md_user", "deleted")]))
        XCTAssertNil(usable([Self.cookie("md_passs", "secret")]))
        XCTAssertNil(usable([]))
        XCTAssertEqual(usable([Self.cookie("md_user", "testeur", expires: now.addingTimeInterval(60))])?.count, 1)
    }

    // MARK: - Helpers

    private func assertFetch(
        _ service: UserProfileService,
        throws expected: UserProfileLoadingError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await service.fetchProfile(url: profileURL)
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? UserProfileLoadingError, expected, file: file, line: line)
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private static func cookie(
        _ name: String,
        _ value: String,
        domain: String = ".hardware.fr",
        expires: Date? = nil
    ) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: "/"]
        if let expires {
            properties[.expires] = expires
        }
        return HTTPCookie(properties: properties)!
    }

    private static func response(for request: URLRequest, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
    }

    private static let profileHTML = """
    <html><body><table class="main">
    <tr class="cBackHeader"><th colspan="2">Informations</th></tr>
    <tr class="profil"><td class="profilCase2">Pseudo&nbsp;:</td><td class="profilCase3">testeur</td></tr>
    </table></body></html>
    """

    private static let forbiddenHTML = """
    <!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
    <html><head><title>403 Forbidden</title></head><body><h1>Forbidden</h1></body></html>
    """
}

private struct SessionProviderStub: UserProfileSessionProviding {
    let cookies: [HTTPCookie]?

    func sessionCookies(for url: URL) -> [HTTPCookie]? {
        cookies
    }
}

private final class AccountsManagerStub: LegacyAccountsManaging {
    private let main: LegacyRawCompte?

    init(main: LegacyRawCompte?) {
        self.main = main
    }

    func comptes() -> [LegacyRawCompte] { main.map { [$0] } ?? [] }
    func mainCompte() -> LegacyRawCompte? { main }
    func currentPseudo() -> String? { main?["PSEUDO"] as? String }
    func currentAccountIdentity() -> LegacyAccountIdentity? { nil }
    func setMainPseudo(_ pseudo: String) {}
    func deletePseudo(at index: Int) {}
    func addCompte(pseudo: String, cookies: [HTTPCookie], avatar: Data?, hash: String?) {}
    func forceCookies(for compte: LegacyRawCompte) {}
    func setHash(_ hash: String, for compte: LegacyRawCompte) {}
}

private final class ProfileURLProtocolStub: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var handledRequests: [URLRequest] = []

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.handledRequests.append(request)
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
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
