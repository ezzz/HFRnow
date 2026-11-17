import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
import Testing
@testable import HFRClient

/// #414: the member's own created smileys, read from the profile edit page 5 in a probe session.
@Suite("Own smileys flow (#414)")
struct OwnSmileysFlowTests {
    private static let cookies = [
        StoredCookie(name: "md_user", value: "fakeuser", domain: ".hardware.fr", path: "/", expiresDate: Date().addingTimeInterval(86_400)),
        StoredCookie(name: "md_passs", value: "fakepass", domain: ".hardware.fr", path: "/", expiresDate: Date().addingTimeInterval(86_400))
    ]
    private static let pageURL = URL(string: "https://forum.hardware.fr/user/editprofil.php") ?? URL(fileURLWithPath: "/")

    private static func flow(_ replies: [Result<HTTPResponse, NetworkError>]) -> (OwnSmileysFlow, MockTransport) {
        let probe = MockTransport(replies: replies)
        return (OwnSmileysFlow(session: HFRSession(cookies: cookies), makeProbe: { _ in probe }), probe)
    }

    @Test("R601a: the member's smileys, from a GET of page 5 only")
    func reads() async throws {
        let (flow, probe) = Self.flow([.success(try Capture.response("R601a-profile-edit-page5-personal-smileys", url: Self.pageURL))])
        let smileys = try await flow.load()
        #expect(smileys.count == 6)
        let requests = await probe.requests
        #expect(requests.count == 1)
        #expect(requests.first?.method == .get)
        #expect(requests.first?.url.path == "/user/editprofil.php")
        #expect(requests.first?.url.query?.contains("page=5") == true)
    }

    @Test("R55-p5: none is an empty list")
    func none() async throws {
        let (flow, _) = Self.flow([.success(try Capture.response("R55-p5-profile-edit-page5", url: Self.pageURL))])
        #expect(try await flow.load().isEmpty)
    }

    @Test("A page without the row is a page error, and a network failure stays one")
    func failures() async throws {
        let empty = HTTPResponse(statusCode: 200, headers: [:], url: Self.pageURL, body: Data("<html></html>".utf8))
        let (other, _) = Self.flow([.success(empty)])
        await #expect(throws: SmileyLookupError.page(.missingElement("tr.profil « Smilies persos »"))) { try await other.load() }
        let (offline, _) = Self.flow([.failure(.timedOut)])
        await #expect(throws: SmileyLookupError.network(.timedOut)) { try await offline.load() }
    }
}
