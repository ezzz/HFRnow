import Foundation
import HFRModels
@testable import SwiftHFR
import Testing
import UIKit
import WebKit

/// What the player sheet may load, and what its "open in browser" fallback may hand to the system.
struct VideoPlayerSheetTests {
    private func url(_ string: String) -> URL { URL(string: string) ?? URL(fileURLWithPath: "/") }

    private func embed(_ provider: EmbedProvider, source: String, player: String) -> MessageEmbed {
        MessageEmbed(provider: provider, sourceURL: url(source), embedURL: url(player))
    }

    @Test(arguments: [
        ("https://www.youtube.com/embed/a", EmbedProvider.youtube, true),
        ("http://player.vimeo.com/video/1", EmbedProvider.vimeo, false),
        ("https://www.youtube.com/embed/a", EmbedProvider.vimeo, false),
        ("https://streamable.com:8443/s/x", EmbedProvider.streamable, false)
    ])
    func thePlayerLoadsOnlyHttpsOnItsProviderHost(player: String, provider: EmbedProvider, loads: Bool) {
        let item = embed(provider, source: "https://example.com/v", player: player)
        #expect((VideoPlayerSheet.playerURL(for: item) != nil) == loads)
    }

    @Test func theBrowserFallbackIsTheOriginalLinkAndHttpOrHttpsOnly() {
        let web = embed(.youtube, source: "https://www.youtube.com/watch?v=a", player: "https://www.youtube.com/embed/a")
        #expect(VideoPlayerSheet.fallbackURL(for: web) == web.sourceURL)
        let plain = embed(.streamable, source: "http://streamable.com/x", player: "https://streamable.com/s/x")
        #expect(VideoPlayerSheet.fallbackURL(for: plain) == plain.sourceURL)
        let other = embed(.youtube, source: "tel:123", player: "https://www.youtube.com/embed/a")
        #expect(VideoPlayerSheet.fallbackURL(for: other) == nil)
        let local = embed(.youtube, source: "file:///etc/hosts", player: "https://www.youtube.com/embed/a")
        #expect(VideoPlayerSheet.fallbackURL(for: local) == nil)
    }

    // MARK: Referer for the YouTube player only (#752, LOT-071 R3 exception)

    @MainActor @Test func theYouTubePlayerRequestIdentifiesTheApp() {
        let request = VideoPlayerSheet.playerRequest(
            for: url("https://www.youtube.com/embed/a"), referer: "https://app.example/"
        )
        #expect(request.value(forHTTPHeaderField: "Referer") == "https://app.example/")
        #expect(VideoPlayerSheet.appReferer(bundleIdentifier: "hfrplus.red.super") == "https://hfrplus.red.super/")
        #expect(VideoPlayerSheet.appReferer(bundleIdentifier: "Com.Example.App") == "https://com.example.app/")
        #expect(VideoPlayerSheet.refererHosts == ["www.youtube.com", "youtube.com", "www.youtube-nocookie.com"])
    }

    @Test(arguments: [
        "https://player.vimeo.com/video/1", "https://streamable.com/s/x", "https://evil.example/embed/a",
        "https://www.youtube.com.evil.example/embed/a"
    ])
    @MainActor func noOtherPlayerGetsAReferer(player: String) {
        let request = VideoPlayerSheet.playerRequest(for: url(player), referer: "https://app.example/")
        #expect(request.value(forHTTPHeaderField: "Referer") == nil)
    }

    /// A loaded player: the stand-in server, the web view, its delegate and the window showing it (kept alive together).
    private struct Loaded {
        let server: RequestRecordingServer
        let webView: WKWebView
        let coordinator: PlayerWebView.Coordinator
        let window: UIWindow?
        /// The player's request reached the server before the deadline.
        let requested: Bool
    }

    /// A real web view loading the request the sheet builds: the loopback host stands for the provider's. The web view is
    /// shown in a window, as in the sheet: in no window, these tests took 245-268 s on CI even when green (`hostInWindow`).
    /// Returns once the server got the request, or at the deadline (`requested` says which).
    @MainActor
    private func load(
        _ refererHosts: Set<String>, status: Int = 200, failure: @escaping () -> Void = {}
    ) async throws -> Loaded {
        let server = try RequestRecordingServer(status: status)
        try await server.ready()
        let target = url("http://127.0.0.1:\(server.port)/embed/a")
        let request = VideoPlayerSheet.playerRequest(
            for: target, referer: "https://app.example/", refererHosts: refererHosts
        )
        let coordinator = PlayerWebView.Coordinator(host: "127.0.0.1", onFailure: failure)
        let webView = PlayerWebView.makeWebView(request: request, delegate: coordinator)
        let window = hostInWindow(webView)
        let requested = await server.firstRequest()
        return Loaded(server: server, webView: webView, coordinator: coordinator, window: window, requested: requested)
    }

    @MainActor @Test func theWebViewSendsTheRefererOnTheWireForYouTubeOnly() async throws {
        let youtube = try await load(["127.0.0.1"])
        defer { youtube.server.stop() }
        let vimeo = try await load([])
        defer { vimeo.server.stop() }
        #expect(youtube.requested && vimeo.requested, "no request reached the stand-in server before the deadline")
        #expect(
            youtube.server.requests.count == 1 && youtube.server.header("Referer") == "https://app.example/",
            "\(youtube.server.requests)"
        )
        #expect(vimeo.server.requests.count == 1 && vimeo.server.header("Referer") == nil, "\(vimeo.server.requests)")
        withExtendedLifetime((youtube, vimeo)) {}
    }

    @Test(arguments: [(200, false), (301, false), (399, false), (401, true), (404, true), (503, true)])
    func onlyAnErrorStatusMakesThePlayerUnavailable(status: Int, fails: Bool) {
        #expect(VideoPlayerSheet.isFailure(statusCode: status) == fails)
    }

    @MainActor @Test func aPlayerThatAnswers401ReportsItAndAHealthyOneDoesNot() async throws {
        var failures = 0
        let reported = TestEvent()
        let bad = try await load([], status: 401) {
            failures += 1
            reported.fire()
        }
        defer { bad.server.stop() }
        let badReported = await reported.wait(timeout: .seconds(120))
        #expect(
            badReported && failures >= 1,
            "the 401 player reported \(failures) failure(s); wire heads: \(bad.server.requests.count) request(s)"
        )
        var healthyFailures = 0
        let good = try await load([]) { healthyFailures += 1 }
        defer { good.server.stop() }
        // Wait for the request (in `load`), then for the end of the load, before asserting that nothing was reported.
        let finished = TestEvent()
        let observation = good.webView.observe(\.isLoading, options: [.initial, .new]) { webView, _ in
            MainActor.assumeIsolated {
                if !webView.isLoading { finished.fire() }
            }
        }
        let loadEnded = await finished.wait(timeout: .seconds(120))
        observation.invalidate()
        // A failure is reported by the delegate right around the end of the load: leave it the time to arrive.
        try await Task.sleep(for: .milliseconds(300))
        #expect(
            good.requested && good.server.requests.count == 1 && loadEnded && !good.webView.isLoading,
            "healthy player: \(good.server.requests.count) request(s), isLoading=\(good.webView.isLoading)"
        )
        #expect(healthyFailures == 0, "healthy player reported \(healthyFailures) failure(s)")
        withExtendedLifetime((bad, good)) {}
    }

    @Test func afterAFailureTheSheetShowsTheUnavailableViewInsteadOfThePlayer() {
        let item = embed(.vimeo, source: "https://vimeo.com/1", player: "https://player.vimeo.com/video/1")
        #expect(VideoPlayerSheet.playerURL(for: item, failed: false) == item.embedURL)
        #expect(VideoPlayerSheet.playerURL(for: item, failed: true) == nil)
    }

    /// The delegate's report rule, driven directly: no connection timing of the runner involved.
    @MainActor @Test(arguments: [
        (NSURLErrorDomain, NSURLErrorCannotConnectToHost, 1),
        (NSURLErrorDomain, NSURLErrorNotConnectedToInternet, 1),
        (NSURLErrorDomain, NSURLErrorTimedOut, 1),
        (NSURLErrorDomain, NSURLErrorCancelled, 0),
        ("WebKitErrorDomain", 102, 0)
    ])
    func aFailedLoadIsReportedOnceUnlessItWasCancelled(domain: String, code: Int, reports: Int) {
        for provisional in [true, false] {
            var failures = 0
            let coordinator = PlayerWebView.Coordinator(host: "127.0.0.1") { failures += 1 }
            let webView = WKWebView(frame: .zero)
            let error = NSError(domain: domain, code: code)
            if provisional {
                coordinator.webView(webView, didFailProvisionalNavigation: nil, withError: error)
            } else {
                coordinator.webView(webView, didFail: nil, withError: error)
            }
            #expect(failures == reports, "\(domain) \(code) provisional=\(provisional): \(failures) report(s), expected \(reports)")
        }
    }
}
