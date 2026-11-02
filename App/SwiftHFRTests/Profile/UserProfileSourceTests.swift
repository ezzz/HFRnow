import Foundation
import HFRNetwork
import HFRParsing
@testable import SwiftHFR
import Testing

/// The live source (LOT-116): the profile goes through the cookie-less client only, then LOT-027's parser, on the captured
/// profiles `R56a` and `R56b`.
struct UserProfileSourceTests {
    private struct Rig {
        let source: LiveUserProfileSource
        let session: MockTransport
        let anonymous: MockTransport
    }

    private static func page(_ body: Data, at address: String) -> MockTransport {
        MockTransport { _ async throws(NetworkError) -> HTTPResponse in
            HTTPResponse(statusCode: 200, headers: ["Content-Type": "text/html; charset=utf-8"], url: url(address), body: body)
        }
    }

    private func rig(_ capture: String, servedAt address: String) throws -> Rig {
        let body = try LiveTopicPageSourceTests.capture(capture)
        // The session answers too, so a source that used it would get the page and pass the parse checks: only the
        // request counts below catch it.
        let session = Self.page(body, at: address)
        let anonymous = Self.page(body, at: address)
        return Rig(source: LiveUserProfileSource(fetcher: PageFetcher(session: session, anonymous: anonymous)),
                   session: session, anonymous: anonymous)
    }

    @Test func theCapturedProfileIsFetchedWithoutCookiesAndParsed() async throws {
        let rig = try rig("R56b-profile-other-member-anon.html", servedAt: "https://forum.hardware.fr/hfr/profil-910002.htm")
        let profile = try await rig.source.profile(memberID: 910_002)
        #expect(await rig.session.requests.isEmpty)
        let requests = await rig.anonymous.requests
        #expect(requests.map(\.url.absoluteString) == ["https://forum.hardware.fr/hfr/profil-910002.htm"])
        let data = try LiveTopicPageSourceTests.capture("R56b-profile-other-member-anon.html")
        let html = try #require(String(data: data, encoding: .utf8))
        #expect(profile == (try UserProfileParser.parse(html: html)))
        #expect(profile.avatarURL != nil)
        #expect(!profile.personalSmilies.isEmpty)
    }

    /// A page served at another URL (a redirect no capture shows) is not read as a profile, even when it parses as one.
    @Test(arguments: [
        "https://forum.hardware.fr/hfr/profil-910003.htm",
        "https://forum.hardware.fr/",
        "https://evil.example/hfr/profil-910002.htm",
        "http://forum.hardware.fr/hfr/profil-910002.htm",
        "https://forum.hardware.fr:8443/hfr/profil-910002.htm"
    ])
    func aProfileServedElsewhereIsRefused(address: String) async throws {
        let rig = try rig("R56b-profile-other-member-anon.html", servedAt: address)
        await #expect(throws: ListLoadError.unreadable) { try await rig.source.profile(memberID: 910_002) }
    }

    /// A page that is not a profile (a topic page) is `unreadable`, never an empty profile.
    @Test func aPageThatIsNotAProfileIsUnreadable() async throws {
        let rig = try rig("R20-topic-p1-anon.html", servedAt: "https://forum.hardware.fr/hfr/profil-910002.htm")
        await #expect(throws: ListLoadError.unreadable) { try await rig.source.profile(memberID: 910_002) }
    }

    @Test func aTransportFailureIsMapped() async {
        let anonymous = MockTransport { _ async throws(NetworkError) -> HTTPResponse in throw .offline }
        let source = LiveUserProfileSource(fetcher: PageFetcher(session: MockTransport(replies: []), anonymous: anonymous))
        await #expect(throws: ListLoadError.offline) { try await source.profile(memberID: 1) }
    }
}
