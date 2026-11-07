import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// The author menu of the reader (issue #595): Profil and MP, and no Blacklist/Whitelist until LOT-118.
@MainActor
struct AuthorActionHandlerTests {
    private let profile = url("https://forum.hardware.fr/hfr/profil-1234.htm")
    private let mpLink = url("https://forum.hardware.fr/message.php?config=hfr.inc&cat=prive&dest=user1")

    private func context(profile: URL?, mpLink: URL?, own: Bool = false) -> MessageMenuContext {
        MessageMenuContext(
            numreponse: 42, author: "auteur",
            actions: MessageActions(editURL: own ? url("https://forum.hardware.fr/message.php?cat=13&post=1&numreponse=42") : nil,
                                    profileURL: profile, privateMessageURL: mpLink),
            permalinkURL: nil
        )
    }

    @Test func theAuthorMenuOffersProfilAndMPOnly() {
        var opened: [URL] = []
        var targets: [NewMessageTarget] = []
        let registry = MessageActionRegistry([
            ProfileActionHandler { opened.append($0) }, PrivateMessageActionHandler { targets.append($0) }
        ])
        #expect(registry.offers(.avatar) && !registry.offers(.message))
        let entries = registry.entries(for: context(profile: profile, mpLink: mpLink), source: .avatar)
        #expect(entries == [.profile, .privateMessage], "no Blacklist or Whitelist: LOT-118 owns them")
        #expect(opened.isEmpty && targets.isEmpty)
    }

    @Test func profilOpensTheLinkAndMPTheComposerTarget() async {
        var opened: [URL] = []
        var targets: [NewMessageTarget] = []
        let registry = MessageActionRegistry([
            ProfileActionHandler { opened.append($0) }, PrivateMessageActionHandler { targets.append($0) }
        ])
        let context = context(profile: profile, mpLink: mpLink)
        #expect(await registry.perform(.profile, with: context))
        #expect(await registry.perform(.privateMessage, with: context))
        #expect(opened == [profile])
        #expect(targets.map(\.recipient) == ["user1"] && targets.first?.formURL == mpLink)
    }

    @Test func entriesFollowTheMessagesLinks() {
        let registry = MessageActionRegistry([ProfileActionHandler { _ in }, PrivateMessageActionHandler { _ in }])
        #expect(registry.entries(for: context(profile: nil, mpLink: mpLink), source: .avatar) == [.privateMessage])
        #expect(registry.entries(for: context(profile: profile, mpLink: nil), source: .avatar) == [.profile])
        // Your own message has no MP entry (policy).
        #expect(registry.entries(for: context(profile: profile, mpLink: mpLink, own: true), source: .avatar) == [.profile])
    }

    @Test func aPrivateMessageLinkOffTheForumOrNotPrivateIsNotOffered() {
        let registry = MessageActionRegistry([PrivateMessageActionHandler { _ in }])
        let foreign = url("https://example.com/message.php?cat=prive&dest=user1")
        let notPrivate = url("https://forum.hardware.fr/message.php?config=hfr.inc&cat=13&post=1&numreponse=2")
        let insecure = url("http://forum.hardware.fr/message.php?config=hfr.inc&cat=prive&dest=user1")
        for link in [foreign, notPrivate, insecure] {
            #expect(registry.entries(for: context(profile: nil, mpLink: link), source: .avatar).isEmpty, "\(link)")
        }
    }

    @Test func theAuthorMenuOpensFromTheAvatarTap() async throws {
        let pages = FakeTopicPages { _ in
            ReaderPage(
                topicID: readerTopic, title: "Sujet", currentPage: 1, maxPage: 1,
                messages: [ReaderMessage(
                    numreponse: 7, author: "auteur", isDeleted: false, isContinuation: false, avatarURL: nil,
                    dateText: "27-10-2026 10:00:00", editNote: nil, quotedByCount: nil, content: MessageContent(html: "<p>x</p>"),
                    actions: MessageActions(profileURL: profile, privateMessageURL: mpLink)
                )],
                pageURL: url("https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm")
            )
        }
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic), page: 1), source: pages)
        reader.install(MessageActionRegistry([ProfileActionHandler { _ in }, PrivateMessageActionHandler { _ in }]))
        await reader.onAppear()
        #expect(reader.hasAuthorMenus && !reader.hasMessageMenus)
        let token = try #require(reader.document?.token)
        let anchor = CGRect(x: 10, y: 20, width: 40, height: 40)
        reader.requestMenu(post: 7, source: .avatar, anchor: anchor, token: token)
        #expect(reader.presentedMenu?.entries == [.profile, .privateMessage])
        #expect(reader.presentedMenu?.anchor == anchor)
    }
}
