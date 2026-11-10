import Foundation
@testable import SwiftHFR
import Testing

/// The wording of the VoiceOver announcements (LOT-163).
struct ReaderAccessibilityTests {
    @Test func aPageChangeIsAnnouncedWithItsNumberAndTheCount() {
        #expect(ReaderAccessibility.pageAnnouncement(from: 2, to: 3, maxPage: 12) == "Page 3 sur 12")
        #expect(ReaderAccessibility.pageAnnouncement(from: 12, to: 1, maxPage: 12) == "Page 1 sur 12")
    }

    @Test func theFirstLoadARefreshAndASinglePageSayNothing() {
        #expect(ReaderAccessibility.pageAnnouncement(from: nil, to: 3, maxPage: 12) == nil)
        #expect(ReaderAccessibility.pageAnnouncement(from: 3, to: 3, maxPage: 12) == nil)
        #expect(ReaderAccessibility.pageAnnouncement(from: 3, to: nil, maxPage: 12) == nil)
        #expect(ReaderAccessibility.pageAnnouncement(from: 1, to: 2, maxPage: 1) == nil)
    }

    @Test func eachViewerPictureIsNamedByItsPlace() {
        #expect(ReaderAccessibility.imageLabel(position: 1, count: 5) == "Image 2 sur 5")
        #expect(ReaderAccessibility.imageLabel(position: 0, count: 1) == "Image")
    }
}

/// What `reader.js` adds for VoiceOver, in a real web view (LOT-163): attributes only, shaped as HFR's own tables.
@Suite(.serialized)
@MainActor
struct ReaderAccessibilityAdapterTests: ReaderWebTesting {
    private let content = """
        <table class="citation"><tr class="none"><td><b class="s1"><a href="/hfr/x_1.htm#t1" class="Topic">user4 a écrit :</a></b>\
        <br><br><p>texte</p></td></tr></table>
        <table class="citation quote-blocked quote-hide-author"><tr class="none"><td><b class="s1">\
        <a href="/hfr/x_1.htm#t2" class="Topic">user9 a écrit :</a></b><br><br><p>texte</p></td></tr></table>
        <table class="code"><tr class="none"><td><b class="s1">Code :</b><br><ol class="olcode"><li>a</li></ol></td></tr></table>
        <table class="spoiler"><tr class="none"><td><b class="s1Topic">Spoiler :</b><br><br>\
        <div class="Topic masque"><p><img class="hfrplusimg" src="https://forum-images.hardware.fr/images/a.png" \
        alt="https://forum-images.hardware.fr/images/a.png"></p></div>\
        </td></tr></table>
        <p><img class="hfrplusimg" src="https://forum-images.hardware.fr/images/b.png"></p>
        <p><img class="hfrplusimg" src="https://forum-images.hardware.fr/images/c.png" alt="photo"></p>
        """

    /// Runs `body` on the shown page; the recorder holds the window, so it lives as long as the body.
    private func onShownPage(_ body: (ReaderWebController) async throws -> Void) async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.show(document(token: 1, content: content))
        #expect(await until { recorder.ready == [1] })
        #expect(await settled(controller))
        try await body(controller)
        withExtendedLifetime(recorder) {}
    }

    /// The attribute's value, nil when it is absent (or the script failed, which every expectation here would then catch).
    private func attribute(_ name: String, of selector: String, in controller: ReaderWebController) async -> String? {
        let script = "return document.querySelector('\(selector)')?.getAttribute('\(name)') ?? null;"
        return (try? await evaluate(script, in: controller)) as? String
    }

    @Test func quotesCodeAndSpoilersAreNamedGroupsNotTables() async throws {
        try await onShownPage { controller in
            for selector in ["table.citation", "table.code", "table.spoiler"] {
                #expect(await attribute("role", of: selector, in: controller) == "group")
            }
            #expect(await attribute("aria-label", of: "table.citation", in: controller) == "user4 a écrit :")
            #expect(await attribute("aria-label", of: "table.code", in: controller) == "Code")
            #expect(await attribute("aria-label", of: "table.spoiler", in: controller) == "Spoiler")
        }
    }

    @Test func aBlocklistedQuoteNeverNamesTheAuthorItHides() async throws {
        try await onShownPage { controller in
            #expect(await attribute("aria-label", of: "table.quote-blocked", in: controller) == "Citation masquée")
            #expect(await attribute("aria-label", of: "table.quote-blocked b.s1", in: controller) == "Citation masquée")
            #expect(await attribute("aria-expanded", of: "table.quote-blocked b.s1", in: controller) == "false")
        }
    }

    @Test func theSpoilerHeaderIsAButtonWhoseStateFollowsTheTap() async throws {
        try await onShownPage { controller in
            let header = "table.spoiler b.s1Topic"
            #expect(await attribute("role", of: header, in: controller) == "button")
            #expect(await attribute("tabindex", of: header, in: controller) == "0")
            #expect(await attribute("aria-expanded", of: header, in: controller) == "false")
            _ = try await evaluate("document.querySelector('\(header)').click(); return true;", in: controller)
            #expect(await attribute("aria-expanded", of: header, in: controller) == "true")
            // The keyboard does what the tap does (Full Keyboard Access, switch control).
            _ = try await evaluate(
                "document.querySelector('\(header)').dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));"
                + " return true;",
                in: controller
            )
            #expect(await attribute("aria-expanded", of: header, in: controller) == "false")
        }
    }

    @Test func anOpenedBlocklistedQuoteGivesItsLinkBackAndShowsItsAuthor() async throws {
        try await onShownPage { controller in
            _ = try await evaluate("document.querySelector('table.quote-blocked b.s1').click(); return true;", in: controller)
            #expect(await attribute("role", of: "table.quote-blocked b.s1", in: controller) == nil)
            #expect(await attribute("aria-label", of: "table.quote-blocked b.s1", in: controller) == nil)
            #expect(await attribute("aria-label", of: "table.quote-blocked", in: controller) == "user9 a écrit :")
        }
    }

    @Test func aPostedPictureWithoutARealDescriptionIsReadAsImage() async throws {
        try await onShownPage { controller in
            let script = "return Array.from(document.querySelectorAll('img.hfrplusimg')).map((i) => i.getAttribute('alt'));"
            let alts = (try? await evaluate(script, in: controller)) as? [String]
            // An address as alt (HFR's own), a missing alt: "Image"; a real description stays.
            #expect(alts == ["Image", "Image", "photo"])
        }
    }
}
