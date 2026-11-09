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

    @Test(arguments: [
        "https://example.org/a/photo.jpg", "https://example.org/a/PHOTO.PNG?x=1", "https://forum-images.hardware.fr/a/b.gif",
        "https://reho.st/thumb/abc", "https://img3.super-h.fr/images/a.th.x", "https://rehost.diberie.com/Picture/Get/t/12"
    ])
    func anImageLinkGetsTheTwoImageEntriesAfterOpen(link: String) throws {
        let url = try #require(URL(string: link))
        let entries = ReaderLinkMenu.entries(for: url)
        #expect(Array(entries.prefix(5)) == [.open, .openImage, .saveImage, .copy, .safari])
        #expect(entries.map(\.title).prefix(3) == ["Ouvrir", "Ouvrir l'image", "Enregistrer dans Photos"])
    }

    @Test(arguments: [
        "https://example.org/page", "https://example.org/photo.jpg.html", "http://192.168.1.1/a.jpg", "http://localhost/a.png"
    ])
    func aLinkThatIsNotAnImageOrIsBlockedHasNoImageEntry(link: String) throws {
        let url = try #require(URL(string: link))
        #expect(!ReaderLinkMenu.entries(for: url).contains(.openImage))
        #expect(!ReaderLinkMenu.entries(for: url).contains(.saveImage))
    }

    @Test func openImageOpensTheViewerOnThatImageWithoutRequestingIt() {
        let transport = quietTransport()
        let (controller, recorder) = makeController(transport: transport)
        let image = URL(string: "https://example.org/a/photo.jpg")!
        controller.performLinkEntry(.openImage, url: image)
        #expect(recorder.viewers.count == 1)
        #expect(recorder.viewers.first?.index == 0)
        #expect(recorder.viewers.first?.images.map(\.shown) == [image])
        #expect(recorder.links.isEmpty)
        #expect(controller.imageRequests.isEmpty)
    }

    @Test func openImageRefusesABlockedHost() {
        let (controller, recorder) = makeController(transport: quietTransport())
        controller.performLinkEntry(.openImage, url: URL(string: "http://192.168.1.1/a.jpg")!)
        #expect(recorder.viewers.isEmpty)
    }

    @Test func saveImageDownloadsCookieLessThenSavesTheBytes() async throws {
        let bytes = Data([1, 2, 3])
        let transport = MockTransport { request in
            HTTPResponse(statusCode: 200, headers: ["Content-Type": "image/jpeg"], url: request.url, body: bytes)
        }
        let (controller, recorder) = makeController(transport: transport)
        let spy = EnvironmentSpy()
        controller.linkMenuEnvironment = spy.environment
        controller.performLinkEntry(.saveImage, url: URL(string: "https://example.org/a/photo.jpg")!)
        #expect(await until { !recorder.notices.isEmpty })
        #expect(spy.saved == [bytes])
        #expect(recorder.notices == ["Photo enregistrée"])
        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(requests.allSatisfy { $0.url.host() == "example.org" })
    }

    @Test func saveImageSaysWhenTheDownloadFails() async {
        let (controller, recorder) = makeController(transport: quietTransport())
        let spy = EnvironmentSpy()
        controller.linkMenuEnvironment = spy.environment
        controller.performLinkEntry(.saveImage, url: URL(string: "https://example.org/a/photo.jpg")!)
        #expect(await until { !recorder.notices.isEmpty })
        #expect(recorder.notices == ["Erreur réseau"])
        #expect(spy.saved.isEmpty)
    }

    @Test(arguments: [
        (ImageSaveError.permissionDenied, "Autorise l'accès aux Photos pour enregistrer l'image."),
        (ImageSaveError.invalidImage, "Impossible d'enregistrer cette image."),
        (ImageSaveError.system, "L'enregistrement dans Photos a échoué.")
    ])
    func saveImageReportsWhyPhotosRefused(error: ImageSaveError, sentence: String) async {
        let transport = MockTransport { request in
            HTTPResponse(statusCode: 200, headers: ["Content-Type": "image/png"], url: request.url, body: Data([9]))
        }
        let (controller, recorder) = makeController(transport: transport)
        let spy = EnvironmentSpy(saveError: error)
        controller.linkMenuEnvironment = spy.environment
        controller.performLinkEntry(.saveImage, url: URL(string: "https://example.org/a/photo.png")!)
        #expect(await until { !recorder.notices.isEmpty })
        #expect(recorder.notices == [sentence])
    }

    @Test func saveImageNeverRequestsABlockedHost() async {
        let transport = quietTransport()
        let (controller, recorder) = makeController(transport: transport)
        controller.performLinkEntry(.saveImage, url: URL(string: "http://192.168.1.1/a.jpg")!)
        #expect(await until { !recorder.notices.isEmpty })
        #expect(recorder.notices == ["Impossible d'enregistrer cette image."])
        #expect(await transport.requests.isEmpty)
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
        // Safari, then the app attempt (universal links only) and, since no app takes the link, Safari again.
        #expect(await until { spy.opened.count == 3 })
        try await Task.sleep(for: .milliseconds(300))
        #expect(spy.opened.map(\.universalOnly).sorted { !$0 && $1 } == [false, false, true])
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
    /// The bytes handed to Photos; written from a `@Sendable` closure, hence the lock.
    private let savedBytes = Locked<[Data]>([])
    var saved: [Data] { savedBytes.value }
    private let appTakesLinks: Bool
    private let saveError: ImageSaveError?

    init(appTakesLinks: Bool = false, saveError: ImageSaveError? = nil) {
        self.appTakesLinks = appTakesLinks
        self.saveError = saveError
    }

    var environment: ReaderLinkMenu.Environment {
        ReaderLinkMenu.Environment(
            open: { [self] url, universalOnly in
                opened.append(Opened(url: url, universalOnly: universalOnly))
                return universalOnly ? appTakesLinks : true
            },
            copy: { [self] url in copied.append(url) },
            savePhoto: { [saveError, savedBytes] data async throws(ImageSaveError) in
                if let saveError { throw saveError }
                savedBytes.withValue { $0.append(data) }
            }
        )
    }
}

/// A value shared with `@Sendable` closures.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value { lock.withLock { stored } }

    func withValue(_ change: (inout Value) -> Void) { lock.withLock { change(&stored) } }
}
