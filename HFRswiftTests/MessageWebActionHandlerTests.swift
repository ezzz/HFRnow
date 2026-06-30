import XCTest
@testable import HFRswift

@MainActor
final class MessageWebActionHandlerTests: XCTestCase {
    private let handler = MessageWebActionHandler()

    func testAutoNextLoadsNextPageFromLinkActivated() {
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdoauto://next")!,
            navigationType: .linkActivated,
            currentPage: 5,
            maxPage: 10
        )

        XCTAssertEqual(action, .loadPage(6, .top))
    }

    func testAutoBeginLoadsFirstPageWithTopScroll() {
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdoauto://begin")!,
            navigationType: .linkActivated,
            currentPage: 6,
            maxPage: 10
        )

        XCTAssertEqual(action, .loadPage(1, .top))
    }

    func testAutoEndLoadsLastPageWithBottomScroll() {
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdoauto://end")!,
            navigationType: .linkActivated,
            currentPage: 6,
            maxPage: 10
        )

        XCTAssertEqual(action, .loadPage(10, .bottom))
    }

    func testAutoPreviousAtFirstPageIsIgnored() {
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdoauto://previous")!,
            navigationType: .linkActivated,
            currentPage: 1,
            maxPage: 10
        )

        XCTAssertEqual(action, .ignore)
    }

    func testRefreshSchemeTriggersRefreshAction() {
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdorefresh://data")!,
            navigationType: .other,
            currentPage: 3,
            maxPage: 10
        )

        XCTAssertEqual(action, .refreshCurrentPage)
    }

    func testLoadedSchemeIsIgnored() {
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdoloaded://data")!,
            navigationType: .other,
            currentPage: 3,
            maxPage: 10
        )

        XCTAssertEqual(action, .ignore)
    }

    func testPopupAvatarSchemeProducesPopupMenuAction() {
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdopopupavatar://152/27")!,
            navigationType: .other,
            currentPage: 3,
            maxPage: 10
        )

        XCTAssertEqual(
            action,
            .showPopupMenu(
                MessageWebPopupPayload(
                    source: .avatar,
                    messageIndex: 27,
                    yOffset: 152,
                    xOffset: nil
                )
            )
        )
    }

    func testPopupMessageSchemeProducesPopupMenuAction() {
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdopopupmessage://88/4")!,
            navigationType: .other,
            currentPage: 3,
            maxPage: 10
        )

        XCTAssertEqual(
            action,
            .showPopupMenu(
                MessageWebPopupPayload(
                    source: .message,
                    messageIndex: 4,
                    yOffset: 88,
                    xOffset: nil
                )
            )
        )
    }

    func testPopupAvatarSchemeWithXAndYProducesPopupMenuAction() {
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdopopupavatar://231/88/27")!,
            navigationType: .other,
            currentPage: 3,
            maxPage: 10
        )

        XCTAssertEqual(
            action,
            .showPopupMenu(
                MessageWebPopupPayload(
                    source: .avatar,
                    messageIndex: 27,
                    yOffset: 88,
                    xOffset: 231
                )
            )
        )
    }

    func testPopupMessageSchemeWithXAndYProducesPopupMenuAction() {
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdopopupmessage://231/88/4")!,
            navigationType: .other,
            currentPage: 3,
            maxPage: 10
        )

        XCTAssertEqual(
            action,
            .showPopupMenu(
                MessageWebPopupPayload(
                    source: .message,
                    messageIndex: 4,
                    yOffset: 88,
                    xOffset: 231
                )
            )
        )
    }

    func testPopupSchemeWithoutMessageIndexIsIgnored() {
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdopopupmessage://invalid")!,
            navigationType: .other,
            currentPage: 3,
            maxPage: 10
        )

        XCTAssertEqual(action, .ignore)
    }

    func testPopupMessageWithNonNumericHostKeepsYOffsetAndMessageIndex() {
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdopopupmessage://x/88/4")!,
            navigationType: .other,
            currentPage: 3,
            maxPage: 10
        )

        XCTAssertEqual(
            action,
            .showPopupMenu(
                MessageWebPopupPayload(
                    source: .message,
                    messageIndex: 4,
                    yOffset: 88,
                    xOffset: nil
                )
            )
        )
    }

    func testPopupMessageWithOnlyMessageIndexDefaultsYOffsetToZero() {
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdopopupmessage://4")!,
            navigationType: .other,
            currentPage: 3,
            maxPage: 10
        )

        XCTAssertEqual(
            action,
            .showPopupMenu(
                MessageWebPopupPayload(
                    source: .message,
                    messageIndex: 4,
                    yOffset: 0,
                    xOffset: nil
                )
            )
        )
    }

    func testPopupAvatarSchemeWithNoNumericValuesIsIgnored() {
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdopopupavatar://x/y/z")!,
            navigationType: .other,
            currentPage: 3,
            maxPage: 10
        )

        XCTAssertEqual(action, .ignore)
    }

    func testImageBrowserSchemeRoutesToImageViewer() {
        let imageURL = "https%3A%2F%2Fimg3.super-h.fr%2Fimages%2Ffull.jpg"
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdoimbrows://12/\(imageURL)")!,
            navigationType: .other,
            currentPage: 3,
            maxPage: 10
        )

        XCTAssertEqual(
            action,
            .presentImageViewer(URL(string: "https://img3.super-h.fr/images/full.jpg")!)
        )
    }

    func testImageBrowserSchemeWithInvalidURLIsIgnored() {
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdoimbrows://12/not_a_url")!,
            navigationType: .other,
            currentPage: 3,
            maxPage: 10
        )

        XCTAssertEqual(action, .ignore)
    }

    func testImageBrowserSchemeNormalizesSuperHThumbnail() {
        let imageURL = "https%3A%2F%2Fimg3.super-h.fr%2Fimages%2F2026%2F06%2F18%2Fsnapshot_1970926097888085342.th.jpg"
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdoimbrows://12/\(imageURL)")!,
            navigationType: .other,
            currentPage: 3,
            maxPage: 10
        )

        XCTAssertEqual(
            action,
            .presentImageViewer(URL(string: "https://img3.super-h.fr/images/2026/06/18/snapshot_1970926097888085342.jpg")!)
        )
    }

    func testLinkedThumbnailResolverUsesSuperHFullImageForSmallSameImage() {
        let thumbnailURL = URL(string: "https://img3.super-h.fr/images/2026/06/18/snapshot_1970926097888085342.th.jpg")!
        let linkedURL = URL(string: "https://img3.super-h.fr/images/2026/06/18/snapshot_1970926097888085342.jpg")!

        XCTAssertEqual(
            MessageImageViewerURLResolver.linkedFullSizeURL(
                thumbnailURL: thumbnailURL,
                linkedURL: linkedURL,
                imagePixelSize: CGSize(width: 160, height: 120)
            ),
            linkedURL
        )
    }

    func testLinkedThumbnailResolverRequiresSmallImage() {
        let thumbnailURL = URL(string: "https://img3.super-h.fr/images/2026/06/18/snapshot_1970926097888085342.th.jpg")!
        let linkedURL = URL(string: "https://img3.super-h.fr/images/2026/06/18/snapshot_1970926097888085342.jpg")!

        XCTAssertNil(
            MessageImageViewerURLResolver.linkedFullSizeURL(
                thumbnailURL: thumbnailURL,
                linkedURL: linkedURL,
                imagePixelSize: CGSize(width: 320, height: 180)
            )
        )
    }

    func testLinkedThumbnailResolverRejectsDifferentSuperHImage() {
        let thumbnailURL = URL(string: "https://img3.super-h.fr/images/2026/06/18/snapshot_1970926097888085342.th.jpg")!
        let linkedURL = URL(string: "https://img3.super-h.fr/images/2026/06/18/other.jpg")!

        XCTAssertNil(
            MessageImageViewerURLResolver.linkedFullSizeURL(
                thumbnailURL: thumbnailURL,
                linkedURL: linkedURL,
                imagePixelSize: CGSize(width: 160, height: 120)
            )
        )
    }

    func testSmileySchemeRoutesToManageFavoriteAction() {
        let imageURL = "https%253A%252F%252Fforum-images.hardware.fr%252Ficones%252Fsmiley.gif"
        let action = handler.action(
            for: URL(string: "oijlkajsdoihjlkjasdosmiley://smileycode/ezzz/\(imageURL)")!,
            navigationType: .other,
            currentPage: 3,
            maxPage: 10
        )

        XCTAssertEqual(
            action,
            .manageSmileyFavorite(
                MessageWebSmileyPayload(
                    code: "[:ezzz]",
                    imageURL: "https://forum-images.hardware.fr/icones/smiley.gif"
                )
            )
        )
    }

    func testForumTopicURLIsRoutedAsInternalTopic() {
        let url = URL(string: "https://forum.hardware.fr/forum2.php?cat=1&page=55")!
        let action = handler.action(
            for: url,
            navigationType: .linkActivated,
            currentPage: 3,
            maxPage: 10
        )

        XCTAssertEqual(action, .openInternalTopic(url))
    }

    func testForumTopicURLWithBasFragmentAndLinkActivatedIsInternalTopic() {
        let url = URL(string: "https://forum.hardware.fr/forum2.php?cat=1&page=55#bas")!
        let action = handler.action(
            for: url,
            navigationType: .linkActivated,
            currentPage: 3,
            maxPage: 10
        )

        XCTAssertEqual(action, .openInternalTopic(url))
    }

    func testExternalURLIsRoutedAsExternal() {
        let url = URL(string: "https://example.com/path")!
        let action = handler.action(
            for: url,
            navigationType: .linkActivated,
            currentPage: 3,
            maxPage: 10
        )

        XCTAssertEqual(action, .openExternalURL(url))
    }

    func testFileURLIsRoutedAsInternalTopic() {
        let url = URL(string: "file:///tmp/hfr/topic-1.htm")!
        let action = handler.action(
            for: url,
            navigationType: .linkActivated,
            currentPage: 1,
            maxPage: 5
        )

        XCTAssertEqual(action, .openInternalTopic(url))
    }

    func testExternalURLWithOtherNavigationTypeStaysAllowed() {
        let url = URL(string: "https://example.com/path")!
        let action = handler.action(
            for: url,
            navigationType: .other,
            currentPage: 2,
            maxPage: 10
        )

        XCTAssertEqual(action, .allowNavigation)
    }

    func testFragmentBasInOtherNavigationIsIgnored() {
        let url = URL(string: "https://forum.hardware.fr/forum2.php?page=2#bas")!
        let action = handler.action(
            for: url,
            navigationType: .other,
            currentPage: 2,
            maxPage: 10
        )

        XCTAssertEqual(action, .ignore)
    }

    func testUnknownSchemeAllowsNavigation() {
        let action = handler.action(
            for: URL(string: "about:blank")!,
            navigationType: .other,
            currentPage: 2,
            maxPage: 10
        )

        XCTAssertEqual(action, .allowNavigation)
    }
}

final class MessagePopupActionSupportTests: XCTestCase {
    func testNumericPostIDExtractsDigitsFromLegacyToken() {
        XCTAssertEqual(MessagePopupActionSupport.numericPostID(from: "t55767559"), "55767559")
        XCTAssertEqual(MessagePopupActionSupport.numericPostID(from: "post_42"), "42")
    }

    func testNumericPostIDReturnsNilWhenNoDigitsExist() {
        XCTAssertNil(MessagePopupActionSupport.numericPostID(from: nil))
        XCTAssertNil(MessagePopupActionSupport.numericPostID(from: "post"))
    }

    func testFavoriteResponseMessageExtractsHopMessageAndTrimsWhitespace() {
        let html = """
        <html>
          <body>
            <div class="hop">
              Favori ajoute
            </div>
          </body>
        </html>
        """

        XCTAssertEqual(MessagePopupActionSupport.favoriteResponseMessage(from: html), "Favori ajoute")
    }

    func testFavoriteResponseMessageReturnsNilForMissingOrEmptyHop() {
        XCTAssertNil(MessagePopupActionSupport.favoriteResponseMessage(from: "<html></html>"))
        XCTAssertNil(MessagePopupActionSupport.favoriteResponseMessage(from: #"<div class="hop">   </div>"#))
    }

    func testAQRequestBodyUsesLegacyPercentEncodingAndStableFieldOrder() {
        let body = MessagePopupActionSupport.aqRequestBody(
            title: "Titre test",
            topicID: "123",
            topicTitle: "Sujet test",
            pseudo: "Foo Bar",
            postID: "42",
            postURL: "https://forum.hardware.fr/forum2.php?post=42#t42",
            author: "Jean Luc"
        )

        XCTAssertEqual(
            body,
            "alerte_qualitay_id=-1&nom=Titre%20test&topic_id=123&topic_titre=Sujet%20test&pseudo=Foo%20Bar&post_id=42&post_url=https%3A%2F%2Fforum.hardware.fr%2Fforum2.php%3Fpost%3D42%23t42&commentaire=post%20de%20Jean%20Luc"
        )
    }
}
