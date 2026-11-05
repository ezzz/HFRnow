import Foundation
@testable import SwiftHFR
import Testing

/// Which images of a page the viewer may hold (LOT-109): the page's list is a claim, policy C decides.
struct ImageGalleryTests {
    private func build(
        _ sources: [String], selected: Int, consented: Set<String> = [], auto: Bool = false
    ) -> (images: [GalleryImage], index: Int)? {
        ImageGallery.build(sources: sources, selected: selected, consented: consented, autoLoadsThirdParty: auto)
    }

    @Test func aThirdPartyNeighbourTheUserNeverAllowedIsNotInTheGallery() {
        let sources = ["https://i.imgur.com/a.jpg", "https://i.imgur.com/b.jpg", "https://i.imgur.com/c.jpg"]
        let gallery = build(sources, selected: 2, consented: [sources[0], sources[2]])
        #expect(gallery?.images.map(\.shown.absoluteString) == [sources[0], sources[2]])
        #expect(gallery?.index == 1)
    }

    @Test func theSettingThatLoadsThirdPartiesLetsEveryPictureIn() {
        let sources = ["https://i.imgur.com/a.jpg", "https://i.imgur.com/b.jpg"]
        #expect(build(sources, selected: 1, auto: true)?.images.count == 2)
        #expect(build(sources, selected: 1, auto: false) == nil)
    }

    @Test func aBlockedAddressIsNeverInTheGalleryWhateverTheConsent() {
        let lan = "http://192.168.1.1/admin.png"
        let forum = "https://forum-images.hardware.fr/images/a.png"
        let gallery = build([lan, forum], selected: 1, consented: [lan], auto: true)
        #expect(gallery?.images.map(\.shown.absoluteString) == [forum])
        #expect(build([lan, forum], selected: 0, consented: [lan], auto: true) == nil)
    }

    @Test func anIndexOutsideTheListOpensNothing() {
        #expect(build(["https://forum-images.hardware.fr/images/a.png"], selected: 1) == nil)
        #expect(build(["https://forum-images.hardware.fr/images/a.png"], selected: -1) == nil)
        #expect(build([], selected: 0) == nil)
    }

    @Test func aRehostThumbnailAsksForTheFullSizeImageAndKeepsTheThumbnailAsFallback() throws {
        let thumb = "https://reho.st/thumb/self/abc.jpg"
        let gallery = try #require(build([thumb], selected: 0, consented: [thumb]))
        #expect(gallery.images[0].full.absoluteString == "https://reho.st/self/abc.jpg")
        #expect(gallery.images[0].shown.absoluteString == thumb)
        #expect(gallery.images[0].allowsThirdParty)
    }

    @Test func aHostWithoutRewriteRuleKeepsItsURL() throws {
        let url = "https://i.imgur.com/a.jpg"
        let gallery = try #require(build([url], selected: 0, consented: [url]))
        #expect(gallery.images[0].full == gallery.images[0].shown)
    }

    @Test func aForumImageNeverAllowsAThirdPartyRedirect() throws {
        let url = "https://forum-images.hardware.fr/images/a.png"
        let gallery = try #require(build([url], selected: 0))
        #expect(gallery.images[0].allowsThirdParty == false)
    }

    @Test func theGalleryIsBounded() {
        let sources = (0..<(ImageGallery.maximumImages + 50)).map { "https://forum-images.hardware.fr/images/\($0).png" }
        #expect(build(sources, selected: 0)?.images.count == ImageGallery.maximumImages)
        // A picture late on the page still opens, with its neighbours around it.
        let late = ImageGallery.maximumImages + 40
        let gallery = build(sources, selected: late)
        #expect(gallery?.images.count == ImageGallery.maximumImages)
        #expect(gallery.map { $0.images[$0.index].shown.absoluteString } == sources[late])
        #expect(build(sources, selected: sources.count) == nil)
    }
}
