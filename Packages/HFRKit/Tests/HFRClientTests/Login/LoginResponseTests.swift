import Foundation
import HFRNetwork
import Testing
@testable import HFRClient

/// Differential test of the login answer classification against the legacy rule, on every captured login page.
struct LoginResponseTests {
    /// Legacy `LoginService.swift:72-74`: success when the body contains `login_redirection.php`, otherwise
    /// `invalidCredentials`.
    private func legacyAccepts(_ html: String) -> Bool {
        html.contains("login_redirection.php")
    }

    @Test(arguments: [
        ("W01b-login-success-user1", LoginResponse.accepted),
        ("W03-login-success", .accepted),
        ("W01-login-failure", .refused),
        // Not an answer to the POST: the login form page stands for "any other page" (legacy: a refusal).
        ("W00-login-form-anon", .unrecognized)
    ])
    func capturesAgreeWithLegacy(file: String, expected: LoginResponse) throws {
        let html = try Capture.page(file)
        let port = LoginResponse.classify(html)
        #expect(port == expected)
        // The port accepts exactly what legacy accepts; it only splits legacy's refusals into refused / unrecognized.
        #expect((port == .accepted) == legacyAccepts(html))
    }

    /// The facts the flow relies on, read from the capture metadata: one POST answered 200 either way, cookies only
    /// on success, `md_user` among them, and the legacy field order accepted.
    @Test(arguments: [("W01", false), ("W01b", true), ("W03", true)])
    func captureMetadata(id: String, succeeded: Bool) throws {
        let meta = try Capture.meta(id)
        #expect(meta.method == "POST")
        #expect(meta.status == 200)
        #expect(meta.url == "https://forum.hardware.fr/login_validation.php?config=hfr.inc")
        #expect(meta.requestFields == ["pseudo", "password", "action", "login"])
        #expect(meta.setCookieNames == (succeeded ? ["md_user", "md_passs", "md_id"] : []))
        #expect(meta.setCookieNames.contains(HFRSession.identityCookieName) == succeeded)
    }

    /// The profile page 5 read after the login sets the session cookies again: the flow reads the jar after it.
    @Test func profilePageRefreshesTheSessionCookies() throws {
        let meta = try Capture.meta("R55-p5")
        #expect(meta.url == "https://forum.hardware.fr/user/editprofil.php?config=hfr.inc&page=5")
        #expect(Set(meta.setCookieNames) == ["md_user", "md_passs"])
    }

    @Test func requestMatchesTheCapturedBody() throws {
        let request = try HFREndpoint.login(pseudo: "user2", password: "REDACTED")
        let body = request.body.flatMap { String(bytes: $0, encoding: .utf8) }
        let captured = try Capture.meta("W03")
        #expect(request.url.absoluteString == captured.url)
        #expect(body == captured.requestBody)
        #expect(request.headers["Content-Type"] == "application/x-www-form-urlencoded; charset=utf-8")
    }
}
