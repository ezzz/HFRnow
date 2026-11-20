import Foundation
import HFRNetwork
@testable import SwiftHFR
import Testing

private struct OpenedViewer {
    let images: [GalleryImage]
    let index: Int
}

private func link(_ text: String) -> URL { URL(string: text)! } // swiftlint:disable:this force_unwrapping (literals in tests)

/// A picture inside a link (#912): the rules that read the link, the typed message, the controller and the page's tap.
@MainActor
struct ReaderPictureLinkTests: ReaderWebTesting {
    private let base = "https://forum-images.hardware.fr/images"
    private let small = "https://forum-images.hardware.fr/images/small.png"

    @Test func aLinkToAnImageFileOrAKnownRehostOpensThatImage() {
        let big = "https://forum-images.hardware.fr/images/big.png"
        #expect(ReaderPictureTap.decide(shown: small, link: big, autoLoadsThirdParty: false) == .linkedImage(link(big)))
        // The extension is read from the path, in any case, never from the query.
        let upper = "https://forum-images.hardware.fr/images/Big.JPG?x=1"
        #expect(ReaderPictureTap.decide(shown: small, link: upper, autoLoadsThirdParty: false) == .linkedImage(link(upper)))
        #expect(ReaderPictureTap.decide(shown: small, link: "https://forum-images.hardware.fr/page.php?f=a.png", autoLoadsThirdParty: false)
            == .link(link("https://forum-images.hardware.fr/page.php?f=a.png")))
        // A rehost thumbnail linking to the host's own image path (img3 `/images/`, captured as full images in R298).
        let thumb = "https://reho.st/preview/self/abc"
        let img3Thumb = "https://img3.super-h.fr/images/2025/03/26/snapshot_1.th.png"
        let img3Full = "https://img3.super-h.fr/images/2025/03/26/snapshot_1.png"
        #expect(ReaderPictureTap.decide(shown: img3Thumb, link: img3Full, consented: [img3Thumb], autoLoadsThirdParty: false)
            == .linkedImage(link(img3Full)), "the picture's own full size is the one the viewer fetches anyway")
        #expect(ReaderPictureTap.decide(shown: img3Thumb, link: img3Full.replacing("snapshot_1", with: "other"), autoLoadsThirdParty: false)
            != .linkedImage(link(img3Full.replacing("snapshot_1", with: "other"))), "another address needs its own consent")
        // The host alone is not an image: the rehost's home page is a page.
        let home = "https://reho.st/"
        #expect(ReaderPictureTap.decide(shown: thumb, link: home, autoLoadsThirdParty: false) == .link(link(home)))
    }

    /// Captures R298a/b/e: an img3 thumbnail inside a link to the Chevereto viewer page, never to an image. Red before the fix:
    /// the page was taken for an image, fetched, failed, and the viewer showed the thumbnail instead of the full size.
    @Test func anImg3ThumbnailLinkedToItsViewerPageStaysTheViewerOnTheFullSize() {
        let shown = "https://img3.super-h.fr/images/d5e912eb1dcfe4523d4e0ffb8e5e20731b7e016e30e27be7ea040156.th.png"
        let page = "https://img3.super-h.fr/image/gd99"
        #expect(ReaderPictureTap.decide(shown: shown, link: page, autoLoadsThirdParty: false) == .viewer)
        #expect(!ReaderPictureTap.isImage(link(page)))
        // The viewer then opens the table's full size, as before #912.
        let gallery = ImageGallery.build(sources: [shown], selected: 0, consented: [shown], autoLoadsThirdParty: false)
        #expect(gallery?.images.first?.full.absoluteString
            == "https://img3.super-h.fr/images/d5e912eb1dcfe4523d4e0ffb8e5e20731b7e016e30e27be7ea040156.png")
    }

    /// R122c: `reho.st/view/self/<hash>.png` around a `/preview/` thumbnail. No capture shows what `/view/` serves (#1280), so it
    /// is a page link, whatever its extension; so is the host's home page.
    @Test func aRehostViewLinkIsAPageUntilItsCaptureSaysOtherwise() {
        let hash = "cb1f7efe6157caa50541f62a6d98ea6c19d087f6"
        let view = "https://reho.st/view/self/\(hash).png"
        #expect(ReaderPictureTap.decide(shown: "https://reho.st/preview/self/\(hash).png", link: view, autoLoadsThirdParty: false)
            == .link(link(view)))
        let bare = "https://reho.st/self/abc"
        #expect(ReaderPictureTap.decide(shown: "https://reho.st/preview/self/abc", link: bare, autoLoadsThirdParty: false)
            == .link(link(bare)))
    }

    @Test func aLinkToAnythingElseIsALink() {
        #expect(ReaderPictureTap.decide(shown: small, link: "https://example.com/article", autoLoadsThirdParty: false)
            == .link(link("https://example.com/article")))
        let forumList = "https://forum.hardware.fr/forum2.php?config=hfr.inc"
        #expect(ReaderPictureTap.decide(shown: small, link: forumList, autoLoadsThirdParty: true) == .link(link(forumList)))
    }

    @Test func noUsableLinkIsTodaysViewer() {
        #expect(ReaderPictureTap.decide(shown: small, link: nil, autoLoadsThirdParty: false) == .viewer)
        #expect(ReaderPictureTap.decide(shown: small, link: "hfrreader://page/1", autoLoadsThirdParty: false) == .viewer)
        #expect(ReaderPictureTap.decide(shown: small, link: "javascript:alert(1)", autoLoadsThirdParty: false) == .viewer)
        #expect(ReaderPictureTap.decide(shown: small, link: "", autoLoadsThirdParty: false) == .viewer)
    }

    @Test func anImageOnAnotherThirdPartyHostIsNotFetchedWithoutTheSetting() {
        let shown = "https://i.imgur.com/a.jpg"
        let other = "https://cdn.example.org/big.jpg"
        // The user allowed `shown`'s host only: the other host's image is a page to leave for, with the warning.
        #expect(ReaderPictureTap.decide(shown: shown, link: other, autoLoadsThirdParty: false) == .link(link(other)))
        #expect(ReaderPictureTap.decide(shown: shown, link: other, autoLoadsThirdParty: true) == .linkedImage(link(other)))
        // Consent is per address: the same host's other address is not fetched unless it is consented too (strict, #912 review).
        let sameHost = "https://i.imgur.com/big.jpg"
        #expect(ReaderPictureTap.decide(shown: shown, link: sameHost, consented: [shown], autoLoadsThirdParty: false)
            == .link(link(sameHost)))
        #expect(ReaderPictureTap.decide(shown: shown, link: sameHost, consented: [shown, sameHost], autoLoadsThirdParty: false)
            == .linkedImage(link(sameHost)))
        #expect(ReaderPictureTap.decide(shown: shown, link: sameHost, autoLoadsThirdParty: true) == .linkedImage(link(sameHost)))
        // A blocked address is never fetched, whatever the setting: it falls to the link route.
        #expect(ReaderPictureTap.decide(shown: shown, link: "http://192.168.1.1/a.png", autoLoadsThirdParty: true)
            == .link(link("http://192.168.1.1/a.png")))
    }

    @Test func onlyAnExternalPageAsksForConfirmation() throws {
        let page = link("https://example.com/article")
        #expect(PendingPictureLink(.inAppBrowser(page))?.domain == "example.com")
        #expect(PendingPictureLink(.defaultBrowser(page))?.action == .defaultBrowser(page))
        let topic = "https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_4.htm#t401"
        let target = try #require(ReaderTarget(link: topic))
        #expect(PendingPictureLink(.reader(target)) == nil, "a forum link opens in the reader, no warning (LOT-137)")
        #expect(PendingPictureLink(.profile(memberID: 5)) == nil)
        #expect(PendingPictureLink(.ignored) == nil)
    }

    @Test func theMessageCarriesTheLinkAndRejectsABadOne() throws {
        let base: [String: Any] = ["type": "image", "token": 3, "urls": ["a"] as [Any], "index": 0]
        func decoded(_ extra: [String: Any]) -> ReaderBridgeMessage? {
            try? ReaderBridgeMessage.decode(base.merging(extra) { $1 }).message
        }
        #expect(decoded([:]) == .image(urls: ["a"], index: 0, link: nil))
        #expect(decoded(["link": NSNull()]) == .image(urls: ["a"], index: 0, link: nil))
        #expect(decoded(["link": "https://example.com/x"]) == .image(urls: ["a"], index: 0, link: "https://example.com/x"))
        #expect(decoded(["link": 5]) == nil)
        #expect(decoded(["link": ["x"] as [Any]]) == nil)
        let long = "https://example.com/" + String(repeating: "a", count: ReaderBridgeMessage.maximumLinkLength)
        #expect(decoded(["link": long]) == .image(urls: ["a"], index: 0, link: nil))
    }

    @Test func theControllerOpensTheLinkedImageOrReportsThePageLink() {
        let (controller, _) = makeController(transport: imageTransport())
        var opened: [OpenedViewer] = []
        var pages: [URL] = []
        controller.events.image = { images, index, _ in opened.append(OpenedViewer(images: images, index: index)) }
        controller.events.pictureLink = { pages.append($0) }
        let shown = document(token: 2)
        let big = "https://forum-images.hardware.fr/images/big.png"

        _ = controller.handle(.image(urls: [small], index: 0, link: big), in: shown)
        #expect(opened.count == 1)
        #expect(opened.first?.images.first?.shown == link(small))
        #expect(opened.first?.images.first?.full == link(big))
        #expect(pages.isEmpty)

        _ = controller.handle(.image(urls: [small], index: 0, link: "https://example.com/article"), in: shown)
        #expect(opened.count == 1, "no viewer for a page")
        #expect(pages == [link("https://example.com/article")])

        _ = controller.handle(.image(urls: [small], index: 0), in: shown)
        #expect(opened.count == 2)
        #expect(opened.last?.images.first?.full == link(small))
    }

    @Test func aLinkLongerThanTheBridgeKeepsOpensTodaysViewer() throws {
        let (controller, _) = makeController(transport: imageTransport())
        var opened = 0
        var pages: [URL] = []
        controller.events.image = { _, _, _ in opened += 1 }
        controller.events.pictureLink = { pages.append($0) }
        let long = "https://example.com/" + String(repeating: "a", count: ReaderBridgeMessage.maximumLinkLength)
        let payload: [String: Any] = ["type": "image", "token": 2, "urls": [small] as [Any], "index": 0, "link": long]
        let message = try #require(try? ReaderBridgeMessage.decode(payload).message)
        _ = controller.handle(message, in: document(token: 2))
        #expect(opened == 1, "a link dropped by the bridge is no link: today's viewer")
        #expect(pages.isEmpty, "and no page to ask about")
    }

    /// `reader.js` in a real web view: the tap sends the wrapping link, and the page never navigates by itself.
    @Test func aTapOnAPictureInsideALinkSendsTheLink() async throws {
        let content = """
            <p><a href="\(base)/big.png"><img class="hfrplusimg" src="\(small)" alt="a"></a></p>
            <p><a href="https://example.com/article"><img class="hfrplusimg" src="\(base)/b.png" alt="b"></a></p>
            <p><img class="hfrplusimg" src="\(base)/c.png" alt="c"></p>
            """
        let (controller, recorder) = makeController(transport: imageTransport())
        var pages: [URL] = []
        controller.events.pictureLink = { pages.append($0) }
        controller.show(document(token: 1, content: content))
        #expect(await until { recorder.ready == [1] })
        #expect(await settled(controller))

        let pictures = "document.querySelectorAll('img.hfrplusimg')"
        _ = try await evaluate("\(pictures)[0].click(); return true;", in: controller)
        #expect(await until { recorder.viewers.count == 1 })
        #expect(recorder.viewers.first?.images.map(\.full.lastPathComponent) == ["big.png", "b.png", "c.png"])
        #expect(recorder.viewers.first?.index == 0)

        _ = try await evaluate("\(pictures)[1].click(); return true;", in: controller)
        #expect(await until { pages.count == 1 })
        #expect(pages == [link("https://example.com/article")])
        #expect(recorder.viewers.count == 1, "a page link opens no viewer")

        _ = try await evaluate("\(pictures)[2].click(); return true;", in: controller)
        #expect(await until { recorder.viewers.count == 2 })
        #expect(recorder.viewers.last?.images.map(\.full.lastPathComponent) == ["small.png", "b.png", "c.png"])
        #expect(recorder.viewers.last?.index == 2)
        #expect(recorder.links.isEmpty, "the web view never navigated")
    }
}
