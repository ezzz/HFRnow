import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// Port of `HFRswiftTests/MessagePopupMenuPolicyTests.swift` @ 2440d79: same cases, same titles, same order.
struct MessageMenuPolicyTests {
    private static let forum = "https://forum.hardware.fr"
    private static let selection = QuoteSelectionToken(forum: "hardwarefr", topic: readerTopic, numreponse: 42)

    private func context(
        actions: MessageActions = MessageActions(), author: String = "", permalink: Bool = false,
        isFirst: Bool = false, selected: Bool = false, canQualityAlert: Bool = false, canBookmark: Bool = false
    ) -> MessageMenuContext {
        MessageMenuContext(
            numreponse: 42, author: author, actions: actions,
            permalinkURL: permalink ? url("\(Self.forum)/hfr/c/s-sujet_1_1.htm#t42") : nil,
            isFirstPostOfTopic: isFirst, isQuoteSelectionEnabled: selected, canQualityAlert: canQualityAlert, canBookmark: canBookmark
        )
    }

    private func titles(_ context: MessageMenuContext, _ source: MessageMenuSource = .message) -> [String] {
        MessageMenuPolicy.orderedActions(for: context, source: source).map(\.title)
    }

    private func link(_ path: String) -> URL { url(Self.forum + path) }

    @Test func ownMessageKeepsQuoteFirstAndEditThird() {
        let actions = MessageActions(
            quoteURL: link("/message.php?post=42"), editURL: link("/message.php?edit=1"), quoteSelection: Self.selection
        )
        let result = titles(context(actions: actions, permalink: true, canQualityAlert: true, canBookmark: true))
        #expect(Array(result.prefix(3)) == ["Citer", "Citer ☐", "Editer"])
        #expect(result.contains("AQ") && result.contains("Bookmark") && result.contains("Supprimer"))
    }

    @Test func anotherMembersMessageMatchesTheLegacyOrder() {
        let actions = MessageActions(
            quoteURL: link("/message.php?post=42"), alertURL: link("/user/modo.php?numreponse=42"),
            favoriteURL: link("/user/addflag.php?numreponse=42"), quoteSelection: Self.selection
        )
        #expect(titles(context(actions: actions, permalink: true, canQualityAlert: true, canBookmark: true))
            == ["Citer", "Citer ☐", "Favoris", "Link", "Alerter", "AQ", "Bookmark"])
    }

    @Test func theAuthorMenuOffersProfileMPAndTheLists() {
        let actions = MessageActions(
            quoteURL: link("/message.php?post=42"), profileURL: link("/hfr/profil-1.htm"),
            privateMessageURL: link("/message.php?cat=prive&dest=x")
        )
        #expect(titles(context(actions: actions, author: "Pseudo", permalink: true), .avatar)
            == ["Profil", "MP", "Blacklist", "Whitelist"])
    }

    @Test func anOwnMessageHidesMPListsAndAlert() {
        let actions = MessageActions(
            editURL: link("/message.php?edit=1"), alertURL: link("/user/modo.php?numreponse=42"),
            profileURL: link("/hfr/profil-1.htm"), privateMessageURL: link("/message.php?cat=prive&dest=x")
        )
        let ownContext = context(actions: actions, author: "Pseudo", permalink: true)
        let avatar = titles(ownContext, .avatar)
        #expect(avatar == ["Profil"])
        #expect(!titles(ownContext).contains("Alerter"))
    }

    @Test func aBlankAuthorHasNoListEntries() {
        let actions = MessageActions(profileURL: link("/hfr/profil-1.htm"))
        #expect(titles(context(actions: actions, author: " \n"), .avatar) == ["Profil"])
    }

    @Test func alertFallsBackToASingleEntryWithOnlyAPermalink() {
        #expect(titles(context(permalink: true)).filter { $0 == "Alerter" }.count == 1)
    }

    @Test func anAlertLinkDoesNotDuplicateTheFallback() {
        let actions = MessageActions(alertURL: link("/user/modo.php?numreponse=42"))
        #expect(titles(context(actions: actions, permalink: true)) == ["Link", "Alerter"])
    }

    @Test func noPermalinkAndNoAlertLinkOffersNoAlert() {
        #expect(titles(context()) == [])
    }

    @Test func favoriteNeedsTheFlagLink() {
        #expect(!titles(context()).contains("Favoris"))
        #expect(titles(context(actions: MessageActions(favoriteURL: link("/user/addflag.php?numreponse=42")))).contains("Favoris"))
    }

    @Test func deleteNeedsTheEditLinkAndNeverOnTheFirstPost() {
        #expect(!titles(context()).contains("Supprimer"))
        let actions = MessageActions(editURL: link("/message.php?edit=1"))
        #expect(titles(context(actions: actions)).contains("Supprimer"))
        #expect(!titles(context(actions: actions, isFirst: true)).contains("Supprimer"))
        #expect(titles(context(actions: actions, isFirst: true)).contains("Editer"))
    }

    @Test func multiQuoteShowsItsStateAndKeepsTheLinkTitle() {
        let actions = MessageActions(quoteURL: link("/message.php?post=42"), quoteSelection: Self.selection)
        #expect(Array(titles(context(actions: actions, selected: true)).prefix(2)) == ["Citer", "Citer ☑"])
        #expect(MessageMenuAction.link.title == "Link")
    }

    @Test func onlyTheDeletionIsDestructiveAndEveryActionHasASymbol() {
        for kind in MessageMenuAction.Kind.allCases {
            let action = Self.action(of: kind)
            #expect(action.kind == kind)
            #expect(action.systemImageName != "questionmark" && !action.title.isEmpty && action.priority != Int.max)
            #expect(action.isDestructive == (kind == .delete))
        }
    }

    static func action(of kind: MessageMenuAction.Kind) -> MessageMenuAction { MessageMenuAction(kind: kind) }
}
