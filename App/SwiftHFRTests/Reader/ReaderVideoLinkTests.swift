import Foundation
import HFRModels
import HFRNetwork
@testable import SwiftHFR
import Testing

/// #1037: a plain YouTube link of a message shows its thumbnail; a tap opens the YouTube app (universal link only), else Safari.
/// The thumbnail goes through the reader's cookie-less image client under policy C, and falls back to a pill. The LOT-108 players
/// are untouched (`VideoPlayerSheetTests`, `TopicHTMLBuilderTests`).
@MainActor
@Suite(.serialized)
struct ReaderVideoLinkTests: ReaderWebTesting {
    private static let address = "https://youtu.be/dQw4w9WgXcQ?t=5"
    private static let thumbnail = "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"
    /// Nested in `<b>` so it is not one of LOT-035's top-level player candidates (those keep their placeholder, no card).
    private static let plainLink = "<p><b><a class=\"cLink\" href=\"\(address)\">\(address)</a></b></p>"

    // MARK: The markup

    private func html(for content: String, embeds: [MessageEmbed] = []) -> String {
        document(token: 1, content: content, embeds: embeds).html
    }

    @Test func aPlainLinkGetsACardWithThePillAsItsDefault() {
        let page = html(for: Self.plainLink)
        #expect(page.contains("class=\"video-card\" href=\"\(Self.address)\""))
        #expect(page.contains("data-post=\"7\""))
        #expect(page.contains("<img class=\"video-thumb\" src=\"\(Self.thumbnail)\" alt=\"\">"))
        // Without the thumbnail the card reads as the pill, and it names the provider for VoiceOver.
        #expect(page.contains("Vidéo YouTube · toucher pour lire"))
        #expect(page.contains("aria-label=\"Vidéo YouTube\""))
        // The link text stays where the member wrote it.
        #expect(page.contains(">\(Self.address)</a></b>"))
    }

    /// The card's address is the posted text: a `URL` would write `é` as `%C3%A9`, and the reader matches the inline link by it.
    @Test func theCardKeepsTheAddressAsPosted() {
        let posted = "https://youtu.be/dQw4w9WgXcQ?si=é"
        let link = "<p><b><a class=\"cLink\" href=\"\(posted)\">\(posted)</a></b></p>"
        let page = html(for: link)
        #expect(page.contains("class=\"video-card\" href=\"\(posted)\""))
        #expect(!page.contains("%C3%A9"))
    }

    @Test func aTopLevelLinkKeepsOnlyItsPlayerPlaceholder() throws {
        let link = "<p><a class=\"cLink\" href=\"\(Self.address)\">\(Self.address)</a></p>"
        let embed = MessageEmbed(
            provider: .youtube, sourceURL: try #require(URL(string: Self.address)),
            embedURL: try #require(URL(string: "https://www.youtube.com/embed/dQw4w9WgXcQ?start=5")), startSeconds: 5
        )
        let page = html(for: link, embeds: [embed])
        #expect(page.contains("<button type=\"button\" class=\"video\" data-post=\"7\" data-video=\"0\""))
        #expect(!page.contains("video-card"))
    }

    @Test func aNamedLinkOrAChannelGetsNoCard() {
        let named = "<p><b><a class=\"cLink\" href=\"\(Self.address)\">ma vidéo</a></b></p>"
        let channel = "<p><b><a class=\"cLink\" href=\"https://www.youtube.com/@chan\">https://www.youtube.com/@chan</a></b></p>"
        #expect(!html(for: named + channel).contains("video-card"))
    }

    @Test func theCardNeedsNoPolicyBeyondTheImageOne() {
        // The thumbnail is an ordinary image of the page: the CSP still only allows the reader's own scheme.
        #expect(TopicHTMLBuilder.contentSecurityPolicy.contains("img-src hfrreader:"))
        #expect(!html(for: Self.plainLink).contains("<script"))
    }

    // MARK: The thumbnail, through policy C

    private func domCount(_ selector: String, in controller: ReaderWebController) async throws -> Int? {
        let value = try await evaluate("return document.querySelectorAll(\"\(selector)\").length;", in: controller)
        return (value as? NSNumber)?.intValue
    }

    @Test func theThumbnailLoadsThroughTheCookielessClientAndTheCardShowsIt() async throws {
        let transport = imageTransport()
        let (controller, recorder) = makeController(transport: transport, autoLoad: true)
        controller.show(document(token: 1, content: Self.plainLink))
        #expect(await until { recorder.ready == [1] })
        #expect(await until(async: { (try? await domCount(".video-card.has-thumb", in: controller)) == 1 }))
        #expect(await transport.requests.contains { $0.url.absoluteString == Self.thumbnail })
        #expect(await transport.requests.allSatisfy { $0.headers["Cookie"] == nil && $0.headers["Referer"] == nil })
    }

    @Test func aFailedThumbnailLeavesThePill() async throws {
        let transport = MockTransport { request in HTTPResponse(statusCode: 404, url: request.url) }
        let (controller, recorder) = makeController(transport: transport, autoLoad: true)
        controller.show(document(token: 1, content: Self.plainLink))
        #expect(await until { recorder.ready == [1] })
        #expect(await until(async: { (try? await domCount("img.video-thumb", in: controller)) == 0 }))
        #expect(try await domCount(".video-card", in: controller) == 1)
        #expect(try await domCount(".video-card.has-thumb", in: controller) == 0)
        #expect(try await domCount("button.image-tap, .image-link", in: controller) == 0)
    }

    @Test func withImagesOnTapNothingIsRequestedAndThePillShows() async throws {
        let transport = imageTransport()
        let (controller, recorder) = makeController(transport: transport, autoLoad: false)
        controller.show(document(token: 1, content: Self.plainLink))
        #expect(await until { recorder.ready == [1] })
        #expect(await until(async: { (try? await domCount("img.video-thumb", in: controller)) == 0 }))
        #expect(try await domCount(".video-card.has-thumb", in: controller) == 0)
        #expect(try await domCount("button.image-tap", in: controller) == 0)
        #expect(await !transport.requests.contains { $0.url.host() == "i.ytimg.com" })
    }

    // MARK: The tap

    @Test func aTapOnTheCardOrTheLinkOpensTheYouTubeAppThenSafariAndNothingInTheApp() async throws {
        for selector in ["a.video-card", ".content a.cLink"] {
            let (controller, recorder) = makeController(transport: imageTransport(), autoLoad: true)
            let spy = OpenSpy(appTakesLinks: false)
            controller.linkMenuEnvironment = spy.environment
            controller.show(document(token: 1, content: Self.plainLink))
            #expect(await until { recorder.ready == [1] })
            _ = try await evaluate("document.querySelector(\"\(selector)\").click(); return true;", in: controller)
            #expect(await until { spy.opened.count == 2 }, "\(selector)")
            let url = try #require(URL(string: Self.address))
            #expect(spy.opened == [OpenSpy.Opened(url: url, universalOnly: true), OpenSpy.Opened(url: url, universalOnly: false)])
            // No in-app browser (`events.link`), no player sheet (`events.video`), and the page stays where it is.
            #expect(recorder.links.isEmpty && recorder.videos.isEmpty, "\(selector)")
            #expect(controller.webView.url == ReaderWebController.pageURL(token: 1))
        }
    }

    /// Only the message's own text link is the card's link: the same address in a quote, or around a picture, behaves as any link.
    @Test func theSameAddressInAQuoteOrAroundAPictureIsNotTheCard() async throws {
        let quoted = "<table class=\"citation\"><tr><td><a class=\"cLink\" href=\"\(Self.address)\">\(Self.address)</a></td></tr></table>"
        let picture = "<img src=\"https://forum-images.hardware.fr/i.png\">"
        let pictured = "<p><b><a class=\"cLink\" id=\"pic\" href=\"\(Self.address)\">\(picture)</a></b></p>"
        let (controller, recorder) = makeController(transport: imageTransport(), autoLoad: true)
        let spy = OpenSpy(appTakesLinks: false)
        controller.linkMenuEnvironment = spy.environment
        controller.show(document(token: 1, content: Self.plainLink + quoted + pictured))
        #expect(await until { recorder.ready == [1] })
        let url = try #require(URL(string: Self.address))
        _ = try await evaluate("document.querySelector(\"table a.cLink\").click(); return true;", in: controller)
        #expect(await until { recorder.links == [url] })
        _ = try await evaluate("document.getElementById(\"pic\").click(); return true;", in: controller)
        #expect(await until { recorder.links == [url, url] })
        try await Task.sleep(for: .milliseconds(200))
        #expect(spy.opened.isEmpty)
    }

    @Test func whenTheYouTubeAppTakesTheLinkSafariIsNotOpened() async throws {
        let (controller, _) = makeController(transport: imageTransport())
        let spy = OpenSpy(appTakesLinks: true)
        controller.linkMenuEnvironment = spy.environment
        _ = controller.handle(.videoLink(url: Self.address), in: document(token: 1))
        #expect(await until { spy.opened.count == 1 })
        try await Task.sleep(for: .milliseconds(200))
        #expect(spy.opened == [OpenSpy.Opened(url: try #require(URL(string: Self.address)), universalOnly: true)])
    }

    @Test func aPostedHttpLinkIsOpenedOverHTTPS() async throws {
        let (controller, _) = makeController(transport: imageTransport())
        let spy = OpenSpy(appTakesLinks: true)
        controller.linkMenuEnvironment = spy.environment
        _ = controller.handle(.videoLink(url: "http://youtu.be/abc123"), in: document(token: 1))
        #expect(await until { spy.opened.count == 1 })
        #expect(spy.opened.first?.url.absoluteString == "https://youtu.be/abc123")
    }

    /// The page's claim is checked again: only a YouTube video link opens, nothing else the markup could name.
    @Test func aVideoLinkTapThatIsNotAYouTubeVideoOpensNothing() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        let spy = OpenSpy(appTakesLinks: false)
        controller.linkMenuEnvironment = spy.environment
        for claim in ["https://example.org/watch?v=abc", "https://www.youtube.com/@chan", "javascript:alert(1)", "not a url", ""] {
            _ = controller.handle(.videoLink(url: claim), in: document(token: 1))
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(spy.opened.isEmpty && recorder.links.isEmpty)
    }

    @Test func anOpenComposerIgnoresTheTap() async throws {
        let (controller, _) = makeController(transport: imageTransport())
        let spy = OpenSpy(appTakesLinks: false)
        controller.linkMenuEnvironment = spy.environment
        controller.ignoresPageTaps = true
        _ = controller.handle(.videoLink(url: Self.address), in: document(token: 1))
        try await Task.sleep(for: .milliseconds(300))
        #expect(spy.opened.isEmpty)
    }
}

/// Records what the tap handed to the system, and answers like an iPhone with or without the YouTube app.
@MainActor
private final class OpenSpy {
    struct Opened: Equatable {
        let url: URL
        let universalOnly: Bool
    }

    var opened: [Opened] = []
    private let appTakesLinks: Bool

    init(appTakesLinks: Bool) { self.appTakesLinks = appTakesLinks }

    var environment: ReaderLinkMenu.Environment {
        ReaderLinkMenu.Environment(
            open: { [self] url, universalOnly in
                opened.append(Opened(url: url, universalOnly: universalOnly))
                return universalOnly ? appTakesLinks : true
            },
            copy: { _ in },
            savePhoto: { _ async throws(ImageSaveError) in }
        )
    }
}
