import Foundation
import HFRModels
@testable import SwiftHFR
import Testing
import UIKit
import WebKit

/// LOT-117 in the real web view: collapsed quotes and messages open on a tap, and the tinted content is styled.
@MainActor
@Suite(.serialized)
struct VisibilityWebTests: ReaderWebTesting {
    private static let policy = VisibilityPolicy(ownPseudo: "moi", blocklist: ["Troll"], allowlist: ["Ami"])

    private static func quote(_ author: String, inner: String = "") -> String {
        "<table class=\"citation\"><tr class=\"none\"><td><b class=\"s1\"><a href=\"https://forum.hardware.fr/hfr/x-sujet_1_1.htm#t9\" "
            + "class=\"Topic\">\(author) a écrit :</a></b></td></tr>"
            + "<tr><td><div class=\"container\"><p>propos de \(author)</p>\(inner)</div></td></tr></table>"
    }

    private func shown(hidesPseudo: Bool = false) async -> (ReaderWebController, ReaderWebRecorder) {
        let (controller, recorder) = makeController(transport: imageTransport())
        let html = Self.quote("Troll", inner: Self.quote("Inconnu")) + Self.quote("moi") + Self.quote("Ami")
        let quotes = [
            MessageQuote(author: "Troll", depth: 1), MessageQuote(author: "Inconnu", depth: 2),
            MessageQuote(author: "moi", depth: 1), MessageQuote(author: "Ami", depth: 1)
        ]
        func message(_ author: String, _ number: Int, _ body: String, _ quotes: [MessageQuote] = []) -> ReaderMessage {
            ReaderMessage(
                numreponse: number, author: author, isDeleted: false, isContinuation: false, avatarURL: nil,
                dateText: "27-10-2026 10:00:00", editNote: nil, quotedByCount: nil, content: MessageContent(html: body), quotes: quotes
            )
        }
        let page = ReaderPage(
            topicID: readerTopic, title: "Titre", currentPage: 1, maxPage: 1,
            messages: [
                message("Inconnu", 1, html, quotes), message("Troll", 2, "<p>message masqué</p>"),
                message("moi", 3, "<p>mon message</p>"), message("Ami", 4, "<p>message ami</p>")
            ]
        )
        var visibility = Self.policy
        visibility.hidesBlockedPseudo = hidesPseudo
        let options = ReaderRenderOptions(visibility: visibility)
        controller.show(ReaderDocument(
            token: 1, html: TopicHTMLBuilder.document(for: page, token: 1, options: options), anchor: nil, keepsScrollPosition: false
        ))
        #expect(await until { recorder.ready == [1] })
        return (controller, recorder)
    }

    private func number(_ script: String, _ controller: ReaderWebController) async throws -> Int {
        (try await evaluate(script, in: controller) as? NSNumber)?.intValue ?? -1
    }

    @Test func aBlockedQuoteShowsItsHeaderOnlyAndOpensOnATapWithoutFollowingTheLink() async throws {
        let (controller, recorder) = await shown()
        let body = "return getComputedStyle(document.querySelector('table.quote-blocked tr:nth-child(2)')).display;"
        #expect(try await evaluate(body, in: controller) as? String == "none")
        _ = try await evaluate("document.querySelector('table.quote-blocked a.Topic').click(); return true;", in: controller)
        #expect(try await evaluate(body, in: controller) as? String != "none")
        #expect(recorder.links.isEmpty)
        // Open: a tap on the header line (not on its link) closes it again.
        _ = try await evaluate("document.querySelector('table.quote-blocked b.s1').click(); return true;", in: controller)
        #expect(try await evaluate(body, in: controller) as? String == "none")
    }

    @Test func onlyTheHeaderOfABlockedQuoteDrawsAnArrow() async throws {
        let (controller, _) = await shown()
        _ = try await evaluate("document.querySelector('table.quote-blocked a.Topic').click(); return true;", in: controller)
        let content = try await evaluate(
            """
            const after = (element) => getComputedStyle(element, '::after').content;
            const blocked = document.querySelector('table.quote-blocked');
            return [after(blocked.querySelector('b.s1')), after(blocked.querySelectorAll('b.s1')[1])];
            """, in: controller
        ) as? [String]
        #expect(content?.first?.contains("\u{25B2}") == true)
        #expect(content?.last == "none")
    }

    @Test func theQuoteOfMeAndOfAnAllowlistedAuthorStayOpenAndTinted() async throws {
        let (controller, _) = await shown()
        let tinted = try await evaluate(
            """
            const shown = (selector) => getComputedStyle(document.querySelector(selector));
            return [shown('table.quote-me tr:nth-child(2)').display,
                    shown('table.quote-me').borderLeftWidth, shown('table.quote-allowed').borderLeftWidth,
                    shown('table.quote-me').backgroundColor, shown('table.quote-allowed').backgroundColor];
            """, in: controller
        ) as? [String]
        #expect(tinted?.prefix(3).elementsEqual(["table-row", "2px", "2px"]) == true)
        #expect(tinted?[3] != "rgba(0, 0, 0, 0)")
        #expect(tinted?[4] != "rgba(0, 0, 0, 0)")
    }

    @Test func aBlockedMessageIsOneClosedLineUntilTheReaderOpensIt() async throws {
        let (controller, _) = await shown()
        let hidden = "return document.querySelector('article.blocked .content').checkVisibility();"
        #expect(try await evaluate(hidden, in: controller) as? Bool == false)
        let summary = try await evaluate("return document.querySelector('article.blocked summary').textContent;", in: controller) as? String
        #expect(summary == "TrollMessage masqué")
        _ = try await evaluate("document.querySelector('article.blocked summary').click(); return true;", in: controller)
        #expect(try await evaluate(hidden, in: controller) as? Bool == true)
        // Plain messages have no disclosure and the own and allowlisted ones are tinted.
        #expect(try await number("return document.querySelectorAll('details').length;", controller) == 1)
        let tints = try await evaluate(
            """
            return ['article.me .content', 'article.whitelist .content', 'article:not(.me):not(.whitelist):not(.blocked) .content']
              .map((selector) => getComputedStyle(document.querySelector(selector)).borderLeftWidth);
            """, in: controller
        ) as? [String]
        #expect(tints == ["2px", "2px", "0px"])
    }

    @Test func hidingThePseudoRemovesItFromTheCollapsedLine() async throws {
        let (controller, _) = await shown(hidesPseudo: true)
        let summary = try await evaluate("return document.querySelector('article.blocked summary').textContent;", in: controller) as? String
        #expect(summary == "Message masqué")
        let header = try await evaluate(
            "return document.querySelector('table.quote-blocked b.s1').textContent.trim();", in: controller
        ) as? String
        #expect(header?.contains("a écrit") == true) // still in the page, but not drawn while collapsed
        let drawn = try await evaluate(
            "return document.querySelector('table.quote-blocked b.s1 > a').checkVisibility();", in: controller
        ) as? Bool
        #expect(drawn == false)
    }
}
