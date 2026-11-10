import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// LOT-135 with the reader: "Alerter" from the menu of an opened blocked message (issue #225, LOT-117 note).
@MainActor
struct ModeratorAlertReaderTests {
    @Test func alerterWorksFromTheMenuOfAnOpenedBlockedMessage() async throws {
        let blocked = ReaderMessage(
            numreponse: 2666649, author: "Troll", isDeleted: false, isContinuation: false, avatarURL: nil,
            dateText: "27-10-2026 10:00:00", editNote: nil, quotedByCount: nil, content: MessageContent(html: "<p>insulte</p>"),
            actions: MessageActions(alertURL: alertLink)
        )
        let pages = FakeTopicPages { _ in
            ReaderPage(
                topicID: readerTopic, title: "Sujet", currentPage: 1, maxPage: 1, messages: [blocked],
                pageURL: url("https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm")
            )
        }
        let policy = VisibilityPolicy(ownPseudo: "Moi", blocklist: ["Troll"], allowlist: [])
        let reader = TopicReaderModel(
            target: ReaderTarget(source: .topic(readerTopic), page: 1), source: pages,
            renderOptions: { ReaderRenderOptions(visibility: policy) }
        )
        let sentence = "Votre demande de modération sur ce message n'est pas encore traitée."
        let alerter = ScriptedAlerter(.success(.alreadyAlerted(message: sentence)))
        let alerts = ModeratorAlertModel(
            alerter: alerter, mailAddress: nil, confirm: { reader.showMenuFeedback($0) }, openMail: { _ in }
        )
        reader.install(MessageActionRegistry([alerts.handler]))
        await reader.onAppear()

        // The message is collapsed, and its menu button is inside the disclosure the user opens.
        let html = try #require(reader.document?.html)
        let disclosure = try #require(html.components(separatedBy: "<details class=\"blocked-post\">").last)
        #expect(disclosure.contains("class=\"menu-button\" data-menu=\"message\" data-post=\"2666649\""))

        reader.requestMenu(post: 2666649, source: .message, token: try #require(reader.document?.token))
        let menu = try #require(reader.presentedMenu)
        #expect(menu.entries == [.alert])
        await reader.perform(.alert, in: menu)
        #expect(await alerter.links == [alertLink])
        #expect(reader.menuFeedback == sentence)
    }
}
