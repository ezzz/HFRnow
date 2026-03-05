import XCTest
@testable import HFRswift

final class MessagePopupMenuPolicyTests: XCTestCase {
    func testMessageSourceKeepsQuoteActionsFirstAndEditThird() {
        let actions = makeActions(
            quoteURL: url("https://forum.hardware.fr/message.php?post=42"),
            editURL: url("https://forum.hardware.fr/edit.php?post=42"),
            permalinkURL: url("https://forum.hardware.fr/forum2.php?post=42#t42"),
            quoteJS: "javascript:qreply(13,432,61999,55767559); return false;",
            isOwnMessage: true,
            canAQ: true,
            canBookmark: true,
            canDelete: true
        )

        let titles = MessagePopupMenuPolicy.orderedActionKinds(
            for: actions,
            source: .message,
            isQuoteSelectionEnabled: false
        ).map(\.title)

        XCTAssertEqual(Array(titles.prefix(3)), ["Citer", "Citer ☐", "Editer"])
        XCTAssertTrue(titles.contains("AQ"))
        XCTAssertTrue(titles.contains("Bookmark"))
        XCTAssertTrue(titles.contains("Supprimer"))
    }

    func testAvatarSourceIncludesProfileAndModerationActionsForOtherUser() {
        let actions = makeActions(
            quoteURL: url("https://forum.hardware.fr/message.php?post=42"),
            profileURL: url("https://forum.hardware.fr/profil/test"),
            privateMessageURL: url("https://forum.hardware.fr/message.php?cat=prive"),
            editURL: url("https://forum.hardware.fr/edit.php?post=42"),
            permalinkURL: url("https://forum.hardware.fr/forum2.php?post=42#t42"),
            authorName: "Pseudo",
            quoteJS: "javascript:qreply(13,432,61999,55767559); return false;",
            isOwnMessage: false,
            canAQ: true,
            canBookmark: true,
            canDelete: true
        )

        let titles = MessagePopupMenuPolicy.orderedActionKinds(
            for: actions,
            source: .avatar,
            isQuoteSelectionEnabled: false
        ).map(\.title)

        XCTAssertEqual(titles, ["Citer", "Profil", "MP", "Blacklist", "Whitelist"])
    }

    func testOwnMessageHidesMpBlacklistWhitelistAndAlert() {
        let actions = makeActions(
            quoteURL: url("https://forum.hardware.fr/message.php?post=42"),
            profileURL: url("https://forum.hardware.fr/profil/test"),
            privateMessageURL: url("https://forum.hardware.fr/message.php?cat=prive"),
            alertURL: url("https://forum.hardware.fr/alerte.php?post=42"),
            permalinkURL: url("https://forum.hardware.fr/forum2.php?post=42#t42"),
            authorName: "Pseudo",
            isOwnMessage: true
        )

        let titles = MessagePopupMenuPolicy.orderedActionKinds(
            for: actions,
            source: .avatar,
            isQuoteSelectionEnabled: false
        ).map(\.title)

        XCTAssertTrue(titles.contains("Profil"))
        XCTAssertFalse(titles.contains("MP"))
        XCTAssertFalse(titles.contains("Blacklist"))
        XCTAssertFalse(titles.contains("Whitelist"))
        XCTAssertFalse(titles.contains("Alerter"))
    }

    func testAlertFallbackUsesSingleAlerterEntryWhenOnlyPermalinkExists() {
        let actions = makeActions(
            permalinkURL: url("https://forum.hardware.fr/forum2.php?post=42#t42"),
            isOwnMessage: false
        )

        let titles = MessagePopupMenuPolicy.orderedActionKinds(
            for: actions,
            source: .message,
            isQuoteSelectionEnabled: false
        ).map(\.title)

        XCTAssertEqual(titles.filter { $0 == "Alerter" }.count, 1)
    }

    func testDeleteRequiresEditURLEvenWhenCanDeleteFlagIsTrue() {
        let actions = makeActions(
            isOwnMessage: true,
            canDelete: true
        )

        let titles = MessagePopupMenuPolicy.orderedActionKinds(
            for: actions,
            source: .message,
            isQuoteSelectionEnabled: false
        ).map(\.title)

        XCTAssertFalse(titles.contains("Supprimer"))
    }

    func testDeleteIsHiddenForFirstMessageIndex() {
        let actions = makeActions(
            editURL: url("https://forum.hardware.fr/edit.php?post=42"),
            isOwnMessage: true,
            canDelete: true
        )

        let titles = MessagePopupMenuPolicy.orderedActionKinds(
            for: actions,
            source: .message,
            isQuoteSelectionEnabled: false,
            messageIndex: 0
        ).map(\.title)

        XCTAssertFalse(titles.contains("Supprimer"))
    }

    func testQuoteSelectionUsesCheckedTitleWhenCookieStateIsEnabled() {
        let actions = makeActions(
            quoteURL: url("https://forum.hardware.fr/message.php?post=42"),
            quoteJS: "javascript:qreply(13,432,61999,55767559); return false;"
        )

        let titles = MessagePopupMenuPolicy.orderedActionKinds(
            for: actions,
            source: .message,
            isQuoteSelectionEnabled: true
        ).map(\.title)

        XCTAssertEqual(Array(titles.prefix(2)), ["Citer", "Citer ☑"])
    }

    private func makeActions(
        quoteURL: URL? = nil,
        profileURL: URL? = nil,
        privateMessageURL: URL? = nil,
        postID: String? = nil,
        editURL: URL? = nil,
        favoriteURL: URL? = nil,
        alertURL: URL? = nil,
        permalinkURL: URL? = nil,
        authorName: String? = nil,
        quoteJS: String? = nil,
        isOwnMessage: Bool = false,
        canBeFavorite: Bool = false,
        isPrivateCategory: Bool = false,
        canAQ: Bool = false,
        canBookmark: Bool = false,
        canDelete: Bool = false,
        topicID: String? = nil,
        topicCategory: String? = nil,
        topicTitle: String? = nil
    ) -> TopicPageMessageActions {
        TopicPageMessageActions(
            quoteURL: quoteURL,
            profileURL: profileURL,
            privateMessageURL: privateMessageURL,
            postID: postID,
            editURL: editURL,
            favoriteURL: favoriteURL,
            alertURL: alertURL,
            permalinkURL: permalinkURL,
            authorName: authorName,
            quoteJS: quoteJS,
            isOwnMessage: isOwnMessage,
            canBeFavorite: canBeFavorite,
            isPrivateCategory: isPrivateCategory,
            canAQ: canAQ,
            canBookmark: canBookmark,
            canDelete: canDelete,
            topicID: topicID,
            topicCategory: topicCategory,
            topicTitle: topicTitle
        )
    }

    private func url(_ value: String) -> URL {
        URL(string: value)!
    }
}
