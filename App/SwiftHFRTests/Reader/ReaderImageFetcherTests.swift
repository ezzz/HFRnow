import Foundation
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Testing

/// Images go through the cookie-less client, with the policy applied to every redirect hop (LOT-071 R1, R3, edge cases).
struct ReaderImageFetcherTests {
    private func image(_ url: URL, type: String = "image/png", body: Data = Data([1, 2, 3])) -> HTTPResponse {
        HTTPResponse(statusCode: 200, headers: ["Content-Type": type], url: url, body: body)
    }

    private func redirect(from url: URL, to location: String) -> HTTPResponse {
        HTTPResponse(statusCode: 302, headers: ["Location": location], url: url)
    }

    @Test func anImageIsFetchedWithoutCookieNorReferer() async throws {
        let transport = MockTransport { request in self.image(request.url) }
        let fetcher = ReaderImageFetcher(transport: transport)
        let result = try await fetcher.image(at: url("https://i.imgur.com/a.png"), allowsThirdParty: true)
        #expect(result.data == Data([1, 2, 3]))
        #expect(result.mimeType == "image/png")
        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(requests.first?.headers["Cookie"] == nil)
        #expect(requests.first?.headers["Referer"] == nil)
        #expect(requests.first?.redirectPolicy == .doNotFollow)
    }

    @Test func theLiveFetcherUsesTheCookielessTransport() {
        #expect(ReaderImageFetcher().transport is AnonymousTransport)
    }

    @Test func aBlockedURLIsNeverRequested() async {
        let transport = MockTransport { request in self.image(request.url) }
        let fetcher = ReaderImageFetcher(transport: transport)
        for text in ["http://192.168.1.1/a.png", "http://0xC0.0xA8.1.1/a.png", "https://forum.hardware.fr/user/logout.php"] {
            await #expect(throws: ReaderImageFetcher.Failure.refused) {
                try await fetcher.image(at: url(text), allowsThirdParty: true)
            }
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func aThirdPartyImageNeedsPermission() async {
        let transport = MockTransport { request in self.image(request.url) }
        let fetcher = ReaderImageFetcher(transport: transport)
        await #expect(throws: ReaderImageFetcher.Failure.refused) {
            try await fetcher.image(at: url("https://i.imgur.com/a.png"), allowsThirdParty: false)
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func aRedirectToAPrivateAddressStopsBeforeTheSecondRequest() async {
        let transport = MockTransport { request in
            self.redirect(from: request.url, to: "http://192.168.1.1/admin")
        }
        let fetcher = ReaderImageFetcher(transport: transport)
        await #expect(throws: ReaderImageFetcher.Failure.refused) {
            try await fetcher.image(at: url("https://evil.example/a.png"), allowsThirdParty: true)
        }
        #expect(await transport.requests.map(\.url.absoluteString) == ["https://evil.example/a.png"])
    }

    @Test func aForumImageRedirectingToAThirdPartyNeedsPermissionToo() async {
        let transport = MockTransport { request in
            request.url.host() == "forum-images.hardware.fr"
                ? self.redirect(from: request.url, to: "https://tracker.example/p.gif") : self.image(request.url)
        }
        let fetcher = ReaderImageFetcher(transport: transport)
        await #expect(throws: ReaderImageFetcher.Failure.refused) {
            try await fetcher.image(at: url("https://forum-images.hardware.fr/icones/smile.gif"), allowsThirdParty: false)
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func anAllowedRedirectIsFollowed() async throws {
        let transport = MockTransport { request in
            request.url.path() == "/thumb/a.png"
                ? self.redirect(from: request.url, to: "/full/a.png") : self.image(request.url, type: "image/jpeg; charset=binary")
        }
        let fetcher = ReaderImageFetcher(transport: transport)
        let result = try await fetcher.image(at: url("https://reho.st/thumb/a.png"), allowsThirdParty: true)
        #expect(result.mimeType == "image/jpeg")
        #expect(await transport.requests.map(\.url.absoluteString) == ["https://reho.st/thumb/a.png", "https://reho.st/full/a.png"])
    }

    @Test func endlessRedirectsGiveUp() async {
        let transport = MockTransport { request in self.redirect(from: request.url, to: "/again") }
        let fetcher = ReaderImageFetcher(transport: transport)
        await #expect(throws: ReaderImageFetcher.Failure.unavailable) {
            try await fetcher.image(at: url("https://loop.example/a.png"), allowsThirdParty: true)
        }
        #expect(await transport.requests.count == ReaderImageFetcher.maximumRedirects + 1)
    }

    @Test func somethingElseThanAnImageIsRefused() async {
        let transport = MockTransport { request in self.image(request.url, type: "text/html") }
        let fetcher = ReaderImageFetcher(transport: transport)
        await #expect(throws: ReaderImageFetcher.Failure.unavailable) {
            try await fetcher.image(at: url("https://forum-images.hardware.fr/icones/smile.gif"), allowsThirdParty: false)
        }
    }

    @Test func anOversizedImageIsRefused() async {
        let body = Data(count: ReaderImageFetcher.maximumBytes + 1)
        let transport = MockTransport { request in self.image(request.url, body: body) }
        let fetcher = ReaderImageFetcher(transport: transport)
        await #expect(throws: ReaderImageFetcher.Failure.unavailable) {
            try await fetcher.image(at: url("https://i.imgur.com/big.png"), allowsThirdParty: true)
        }
    }

    @Test func httpIsRequestedOverHTTPS() async throws {
        let transport = MockTransport { request in self.image(request.url) }
        let fetcher = ReaderImageFetcher(transport: transport)
        _ = try await fetcher.image(at: url("http://www.hostingpics.net:80/a.png"), allowsThirdParty: true)
        #expect(await transport.requests.map(\.url.absoluteString) == ["https://www.hostingpics.net/a.png"])
    }

    @Test func theImageModeIsTheStoredSettingElseWiFiOnly() {
        let store = InMemorySettingsStore()
        #expect(ReaderSettings.autoLoad(store: store) == .onWiFi)
        store.set(.never, for: SettingKey.displayImages)
        #expect(ReaderSettings.autoLoad(store: store) == .onTap)
        store.set(.always, for: SettingKey.displayImages)
        let settings = ReaderSettings.live(store: store, isOnWiFi: { false })
        #expect(settings.autoLoadsThirdPartyImages())
        store.set(.wifiOnly, for: SettingKey.displayImages)
        #expect(!settings.autoLoadsThirdPartyImages())
        #expect(!settings.renderOptions().showsSignatures)
        store.set(true, for: SettingKey.displaySignatures)
        #expect(settings.renderOptions().showsSignatures)
    }
}
