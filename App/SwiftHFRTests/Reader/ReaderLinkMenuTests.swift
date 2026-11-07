import Foundation
import HFRNetwork
@testable import SwiftHFR
import Testing

/// The long-press menu of a link (#596): which entries, what "Ouvrir" does, and that nothing is ever requested.
@MainActor
@Suite(.serialized)
struct ReaderLinkMenuTests: ReaderWebTesting {
    private let forum = URL(string: "https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm")!
    private let profile = URL(string: "https://forum.hardware.fr/hfr/profil-910002.htm")!
    private let external = URL(string: "https://example.org/page")!
    private let youTube = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!

    private func quietTransport() -> MockTransport {
        MockTransport { request in HTTPResponse(statusCode: 404, url: request.url) }
    }

    @Test func aForumLinkHasNoAppEntry() {
        #expect(ReaderLinkMenu.entries(for: forum) == [.open, .copy, .safari])
        #expect(ReaderLinkMenu.entries(for: profile) == [.open, .copy, .safari])
    }

    @Test func anExternalLinkHasAGenericAppEntry() {
        #expect(ReaderLinkMenu.entries(for: external) == [.open, .copy, .safari, .app(provider: nil)])
        #expect(ReaderLinkMenu.entries(for: external).last?.title == "Ouvrir dans l'app")
    }

    @Test func aVideoHostNamesItsApp() {
        let entries = ReaderLinkMenu.entries(for: youTube)
        #expect(entries.last == .app(provider: .youtube))
        #expect(entries.last?.title == "Ouvrir dans YouTube")
        #expect(ReaderLinkMenu.entries(for: URL(string: "https://vimeo.com/12345")!).last?.title == "Ouvrir dans Vimeo")
    }

    @Test(arguments: ["mailto:a@b.c", "javascript:alert(1)", "hfrreader://page/1", "file:///etc/passwd", "data:text/html,x", "tel:1"])
    func aNonHTTPLinkHasNoEntry(link: String) throws {
        let url = try #require(URL(string: link))
        #expect(ReaderLinkMenu.entries(for: url).isEmpty)
    }

    @Test func aMenuExistsOnlyForALinkElement() {
        let (controller, _) = makeController(transport: quietTransport())
        #expect(controller.linkMenuConfiguration(for: nil) == nil)
        #expect(controller.linkMenuConfiguration(for: external) != nil)
        // Not `http(s)`: an empty menu of ours, never WebKit's default one.
        #expect(controller.linkMenuConfiguration(for: URL(string: "javascript:alert(1)")) != nil)
        #expect(controller.webView.allowsLinkPreview, "WebKit consults the delegate only with link previews on")
    }

    @Test func openTakesTheTapRouting() {
        let (controller, recorder) = makeController(transport: quietTransport())
        controller.performLinkEntry(.open, url: forum)
        controller.performLinkEntry(.open, url: external)
        #expect(recorder.links == [forum, external])
    }

    @Test func copyPutsTheURLOnTheEnvironmentWithoutRouting() {
        let (controller, recorder) = makeController(transport: quietTransport())
        let spy = EnvironmentSpy()
        controller.linkMenuEnvironment = spy.environment
        controller.performLinkEntry(.copy, url: external)
        #expect(spy.copied == [external])
        #expect(recorder.links.isEmpty && spy.opened.isEmpty)
    }

    @Test func safariOpensOutsideTheAppOnce() async {
        let (controller, recorder) = makeController(transport: quietTransport())
        let spy = EnvironmentSpy()
        controller.linkMenuEnvironment = spy.environment
        controller.performLinkEntry(.safari, url: external)
        #expect(await until { spy.opened.count == 1 })
        #expect(spy.opened == [Opened(url: external, universalOnly: false)])
        #expect(recorder.links.isEmpty)
    }

    @Test func appTriesUniversalLinksThenFallsBackToSafari() async {
        let (controller, _) = makeController(transport: quietTransport())
        let spy = EnvironmentSpy(appTakesLinks: false)
        controller.linkMenuEnvironment = spy.environment
        controller.performLinkEntry(.app(provider: .youtube), url: youTube)
        #expect(await until { spy.opened.count == 2 })
        #expect(spy.opened == [Opened(url: youTube, universalOnly: true), Opened(url: youTube, universalOnly: false)])
    }

    @Test func appStopsWhenAnAppTookTheLink() async throws {
        let (controller, _) = makeController(transport: quietTransport())
        let spy = EnvironmentSpy(appTakesLinks: true)
        controller.linkMenuEnvironment = spy.environment
        controller.performLinkEntry(.app(provider: nil), url: external)
        #expect(await until { spy.opened.count == 1 })
        try await Task.sleep(for: .milliseconds(200))
        #expect(spy.opened == [Opened(url: external, universalOnly: true)])
    }

    /// Policy, not a local refusal (LESSONS 56): the menu has no preview and no entry reaches the transport, the session or
    /// the loopback listener a member's link may name.
    @Test func noEntryRequestsTheLink() async throws {
        let server = try ConnectionCounter()
        try await server.ready()
        let transport = quietTransport()
        let (controller, recorder) = makeController(transport: transport)
        let spy = EnvironmentSpy()
        controller.linkMenuEnvironment = spy.environment
        let link = try #require(URL(string: "http://127.0.0.1:\(server.port)/member-link"))
        for entry in ReaderLinkMenu.entries(for: link) { controller.performLinkEntry(entry, url: link) }
        #expect(await until { spy.opened.count == 2 })
        try await Task.sleep(for: .milliseconds(300))
        #expect(server.connections == 0)
        #expect(await transport.requests.isEmpty)
        #expect(recorder.links == [link])
    }
}

private struct Opened: Equatable {
    let url: URL
    let universalOnly: Bool
}

@MainActor
private final class EnvironmentSpy {
    var opened: [Opened] = []
    var copied: [URL] = []
    private let appTakesLinks: Bool

    init(appTakesLinks: Bool = false) { self.appTakesLinks = appTakesLinks }

    var environment: ReaderLinkMenu.Environment {
        ReaderLinkMenu.Environment(
            open: { [self] url, universalOnly in
                opened.append(Opened(url: url, universalOnly: universalOnly))
                return universalOnly ? appTakesLinks : true
            },
            copy: { [self] url in copied.append(url) }
        )
    }
}
