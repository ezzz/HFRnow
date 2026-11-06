import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// Review #330 of LOT-087 against the captures `R63a` and `R63e` (the viewer's own topic, public, logged in): the menu policy
/// runs on what LOT-031's parser reads from the real toolbars. Posts 1, 6 and 9 are the viewer's, the other nine are another
/// member's; `R63a` and `R63e` agree (HFR-PROTOCOL §6c, "Own post on a public topic").
@MainActor
struct MessageMenuOwnPostCaptureTests {
    private static let ownPosts: Set<Int> = [9_910_000_001, 9_910_000_006, 9_910_000_009]
    private static let firstPost = 9_910_000_001
    nonisolated private static let captures = ["R63a-public-own-topic-first-page.html", "R63e-public-own-topic-after-restore.html"]

    private static func contexts(of capture: String) throws -> [MessageMenuContext] {
        let page = try LiveTopicPageSourceTests.readerPage(of: capture)
        return page.messages.enumerated().map { index, message in
            MessageMenuContext(
                numreponse: message.numreponse, author: message.author, actions: message.actions,
                permalinkURL: TopicReaderModel.permalink(of: message.numreponse, on: page), isFirstPostOfTopic: index == 0
            )
        }
    }

    private static func titles(_ context: MessageMenuContext, _ source: MessageMenuSource) -> [String] {
        MessageMenuPolicy.orderedActions(for: context, source: source).map(\.title)
    }

    /// What the capture shows: an own post has the edit link, favourite, alert and quote links and no MP link; another
    /// member's post has no edit link and has MP.
    @Test(arguments: captures)
    func theParserReadsTheLinksTheCaptureShows(_ capture: String) throws {
        let contexts = try Self.contexts(of: capture)
        #expect(contexts.count == 12)
        for context in contexts {
            let links = context.actions
            let own = Self.ownPosts.contains(context.numreponse)
            #expect(links.quoteURL != nil && links.quoteSelection != nil && links.favoriteURL != nil && links.alertURL != nil)
            #expect(links.profileURL != nil)
            #expect((links.editURL != nil) == own, "edit link of \(context.numreponse)")
            if own, let edit = links.editURL {
                let items = Dictionary(
                    uniqueKeysWithValues: (URLComponents(url: edit, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                        .map { ($0.name, $0.value ?? "") }
                )
                #expect(edit.path == "/message.php" && edit.fragment == "formulaire", "edit path of \(context.numreponse)")
                let topic = [items["cat"], items["post"], items["subcat"]]
                #expect(topic == ["6", "9900001", "173"], "edit topic of \(context.numreponse)")
                #expect(items["numreponse"] == String(context.numreponse), "edit message of \(context.numreponse)")
            }
            #expect((links.privateMessageURL == nil) == own, "MP link of \(context.numreponse)")
        }
    }

    /// The message menu of an own post: quote, multi-quote, edit, favourite, link and (not on the first post) delete.
    /// No alert: the link is printed on the own post but legacy never offers to alert one's own message (policy, kept).
    @Test(arguments: captures)
    func theMessageMenuOfAnOwnPost(_ capture: String) throws {
        for context in try Self.contexts(of: capture) where Self.ownPosts.contains(context.numreponse) {
            let expected = ["Citer", "Citer ☐", "Editer", "Favoris", "Link"]
                + (context.numreponse == Self.firstPost ? [] : ["Supprimer"])
            #expect(Self.titles(context, .message) == expected, "post \(context.numreponse)")
        }
    }

    /// Another member's post: no edit, no delete, the alert instead.
    @Test(arguments: captures)
    func theMessageMenuOfAnotherMembersPost(_ capture: String) throws {
        for context in try Self.contexts(of: capture) where !Self.ownPosts.contains(context.numreponse) {
            #expect(Self.titles(context, .message) == ["Citer", "Citer ☐", "Favoris", "Link", "Alerter"], "post \(context.numreponse)")
        }
    }

    /// The author menu: profile only on one's own post (no MP, no lists), everything on another member's.
    @Test(arguments: captures)
    func theAuthorMenu(_ capture: String) throws {
        for context in try Self.contexts(of: capture) {
            let expected = Self.ownPosts.contains(context.numreponse) ? ["Profil"] : ["Profil", "MP", "Blacklist", "Whitelist"]
            #expect(Self.titles(context, .avatar) == expected, "post \(context.numreponse)")
        }
    }
}
