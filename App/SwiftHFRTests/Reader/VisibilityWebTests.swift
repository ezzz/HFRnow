import Foundation
import HFRModels
import HFRParsing
@testable import SwiftHFR
import Testing
import UIKit
import WebKit

/// LOT-117 in the real web view, on content from captured pages (sanitized by LOT-034 as the app does): collapsed quotes and
/// messages open on a tap, and the tinted content is styled.
@MainActor
@Suite(.serialized)
struct VisibilityWebTests: ReaderWebTesting {
    private static let pageURL = url("https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm")

    /// The messages of a captured page, content sanitized and quotes read, as `LiveTopicPageSource` builds them.
    private static func captured(_ name: String) throws -> [ReaderMessage] {
        let data = try LiveTopicPageSourceTests.capture(name)
        return try LiveTopicPageSource.parse(
            try #require(String(data: data, encoding: .utf8)), pageURL: pageURL, normalizer: LiveContentNormalizer()
        ).messages
    }

    /// The first message with a quote by `author`; with `nested`, one that holds a quote inside a quote.
    private static func message(in capture: String, quoting author: String, nested: Bool = false) throws -> ReaderMessage {
        try #require(captured(capture).first { message in
            message.quotes.contains { $0.author == author } && (!nested || message.quotes.contains { $0.depth > 1 })
        })
    }

    private func show(
        _ messages: [ReaderMessage], policy: VisibilityPolicy
    ) async -> (ReaderWebController, ReaderWebRecorder) {
        let (controller, recorder) = makeController(transport: imageTransport())
        let page = ReaderPage(topicID: readerTopic, title: "Titre", currentPage: 1, maxPage: 1, messages: messages)
        let options = ReaderRenderOptions(visibility: policy)
        controller.show(ReaderDocument(
            token: 1, html: TopicHTMLBuilder.document(for: page, token: 1, options: options), anchor: nil, keepsScrollPosition: false
        ))
        #expect(await until { recorder.ready == [1] })
        return (controller, recorder)
    }

    private func evaluate(_ script: String, _ controller: ReaderWebController) async throws -> Any? {
        try await evaluate(script, in: controller)
    }

    private func plain(_ author: String, _ number: Int, _ body: String = "<p>texte</p>") -> ReaderMessage {
        ReaderMessage(
            numreponse: number, author: author, isDeleted: false, isContinuation: false, avatarURL: nil,
            dateText: "27-10-2026 10:00:00", editNote: nil, quotedByCount: nil, content: MessageContent(html: body)
        )
    }

    // MARK: Quotes

    @Test func aBlockedQuoteOfACapturedPageShowsItsHeaderOnlyAndOpensOnATapWithoutFollowingAnyLink() async throws {
        let message = try Self.message(in: "R20-topic-p1-anon.html", quoting: "user4")
        let (controller, recorder) = await show([message], policy: VisibilityPolicy(blocklist: ["user4"]))
        let state = """
            const quote = document.querySelector('table.quote-blocked');
            return [quote.querySelector('b.s1').checkVisibility(), quote.querySelector('p').checkVisibility(),
                    quote.querySelector('a.cLink').checkVisibility(), quote.classList.contains('open')];
            """
        #expect(try await evaluate(state, controller) as? [Bool] == [true, false, false, false])
        // Collapsed: a tap opens the quote, even on a link of its body.
        _ = try await evaluate("document.querySelector('table.quote-blocked a.cLink').click(); return true;", controller)
        #expect(try await evaluate(state, controller) as? [Bool] == [true, true, true, true])
        #expect(recorder.links.isEmpty)
        // Open: a body link is a link again.
        _ = try await evaluate("document.querySelector('table.quote-blocked a.cLink').click(); return true;", controller)
        #expect(await until { recorder.links.count == 1 })
        #expect(try await evaluate(state, controller) as? [Bool] == [true, true, true, true])
        // A tap on the body text keeps it open; a tap on the header (not its link) closes it.
        _ = try await evaluate("document.querySelector('table.quote-blocked p').click(); return true;", controller)
        let stillOpen = try await evaluate("return document.querySelector('table.quote-blocked').classList.contains('open');", controller)
        #expect(stillOpen as? Bool == true)
        _ = try await evaluate("document.querySelector('table.quote-blocked b.s1').click(); return true;", controller)
        #expect(try await evaluate(state, controller) as? [Bool] == [true, false, false, false])
    }

    @Test func aQuoteInsideABlockedQuoteHasNoArrowAndKeepsItsOwnHeader() async throws {
        let message = try Self.message(in: "R28-topic-images-videos-anon.html", quoting: "user4", nested: true)
        var policy = VisibilityPolicy(blocklist: ["user4"])
        policy.hidesBlockedPseudo = true
        let (controller, _) = await show([message], policy: policy)
        // Collapsed with the hide setting: the header reads "Citation masquée", without the pseudo.
        let collapsed = try await evaluate(
            """
            const header = document.querySelector('table.quote-blocked > * > tr > td > b.s1');
            return [getComputedStyle(header, '::before').content, header.querySelector('a').checkVisibility()];
            """, controller
        ) as? [Any]
        #expect(collapsed?.first as? String == "\"Citation masquée\"")
        #expect(collapsed?.last as? Bool == false)
        _ = try await evaluate("document.querySelector('table.quote-blocked > * > tr > td > b.s1').click(); return true;", controller)
        let nested = try await evaluate(
            """
            const outer = document.querySelector('table.quote-blocked');
            const inner = outer.querySelector('table');
            const header = inner.querySelector('b.s1');
            return [getComputedStyle(header, '::after').content, getComputedStyle(header, '::before').content,
                    header.checkVisibility(), inner.querySelector('p, td').checkVisibility(),
                    getComputedStyle(outer.querySelector('b.s1'), '::after').content];
            """, controller
        ) as? [Any]
        #expect(nested?[0] as? String == "none")
        #expect(nested?[1] as? String == "none")
        #expect(nested?[2] as? Bool == true)
        #expect(nested?[3] as? Bool == true)
        #expect((nested?[4] as? String)?.contains("\u{25B2}") == true)
    }

    // MARK: Messages

    @Test func theQuoteOfMeAndOfAnAllowlistedAuthorStayOpenAndTinted() async throws {
        let message = try Self.message(in: "R20-topic-p1-anon.html", quoting: "user4")
        let policy = VisibilityPolicy(ownPseudo: "user4")
        let (controller, _) = await show([message], policy: policy)
        let quote = try await evaluate(
            """
            const probe = document.createElement('span');
            probe.style.color = 'var(--action)';
            document.body.append(probe);
            const style = getComputedStyle(document.querySelector('table.quote-me'));
            return [style.backgroundColor, style.borderLeftWidth, style.borderLeftColor, getComputedStyle(probe).color,
                    document.querySelector('table.quote-me p').checkVisibility()];
            """, controller
        ) as? [Any]
        #expect((quote?[0] as? String)?.contains("0.03") == true, "\(String(describing: quote?[0]))")
        #expect(quote?[1] as? String == "2px")
        #expect(quote?[2] as? String == quote?[3] as? String)
        #expect(quote?[4] as? Bool == true)
    }

    @Test func aBlockedMessageIsOneClosedLineAndOwnAndAllowlistedMessagesAreTinted() async throws {
        let policy = VisibilityPolicy(ownPseudo: "moi", blocklist: ["Troll"], allowlist: ["Ami"])
        let (controller, _) = await show(
            [plain("Troll", 1, "<p>message masqué</p>"), plain("moi", 2), plain("Ami", 3), plain("Inconnu", 4)], policy: policy
        )
        let hidden = "return document.querySelector('article.blocked .content').checkVisibility();"
        #expect(try await evaluate(hidden, controller) as? Bool == false)
        let summary = try await evaluate("return document.querySelector('article.blocked summary').textContent;", controller) as? String
        #expect(summary == "TrollMessage masqué")
        _ = try await evaluate("document.querySelector('article.blocked summary').click(); return true;", controller)
        #expect(try await evaluate(hidden, controller) as? Bool == true)
        #expect((try await evaluate("return document.querySelectorAll('details').length;", controller) as? NSNumber)?.intValue == 1)
        let tints = try await evaluate(
            """
            const probe = (value) => { const span = document.createElement('span'); span.style.color = value;
              document.body.append(span); return getComputedStyle(span).color; };
            const style = (selector, part) => getComputedStyle(document.querySelector('article' + selector + ' ' + part));
            return {
              actionColor: probe('var(--action)'), loveBorder: probe('var(--love-border)'),
              meContent: [style('.me', '.content').backgroundColor, style('.me', '.content').borderLeftColor],
              meHeader: [style('.me', '.header').borderLeftWidth, style('.me', '.header').borderLeftColor],
              meAvatarRing: style('.me', '.header').borderLeftWidth,
              loveContent: [style('.whitelist', '.content').backgroundColor, style('.whitelist', '.content').borderLeftColor],
              loveHeader: [style('.whitelist', '.header').backgroundColor, style('.whitelist', '.header').borderLeftColor],
              plainContent: style(':not(.me):not(.whitelist):not(.blocked)', '.content').borderLeftWidth
            };
            """, controller
        ) as? [String: Any]
        let action = tints?["actionColor"] as? String
        let love = tints?["loveBorder"] as? String
        #expect((tints?["meContent"] as? [String])?.first?.contains("0.03") == true)
        #expect((tints?["meContent"] as? [String])?.last == action)
        #expect((tints?["meHeader"] as? [String]) == ["2px", action ?? ""])
        #expect((tints?["loveContent"] as? [String])?.first?.contains("0.4") == true)
        #expect((tints?["loveContent"] as? [String])?.last == love)
        #expect((tints?["loveHeader"] as? [String])?.first?.contains("0.4") == true)
        #expect((tints?["loveHeader"] as? [String])?.last == love)
        #expect(tints?["plainContent"] as? String == "0px")
    }

    @Test func anOpenedBlockedMessageKeepsItsMarginsAndItsBottomPadding() async throws {
        let policy = VisibilityPolicy(blocklist: ["Troll"])
        var message = plain("Troll", 1)
        message.editNote = "Troll le 27-10-2026"
        let (controller, _) = await show([message], policy: policy)
        _ = try await evaluate("document.querySelector('article.blocked summary').click(); return true;", controller)
        let layout = try await evaluate(
            """
            const open = document.querySelector('.blocked-post');
            const left = (element) => element.getBoundingClientRect().left - open.getBoundingClientRect().left;
            return [left(open.querySelector('.header')), left(open.querySelector('.content')), left(open.querySelector('.trailer')),
                    parseFloat(getComputedStyle(open).paddingBottom)];
            """, controller
        ) as? [Double]
        let measured = try #require(layout)
        #expect(measured.prefix(3).allSatisfy { $0 > 8 })
        #expect(measured[3] > 4)
    }

    @Test func hidingThePseudoRemovesItFromTheCollapsedLine() async throws {
        var policy = VisibilityPolicy(blocklist: ["Troll"])
        policy.hidesBlockedPseudo = true
        let (controller, _) = await show([plain("Troll", 1)], policy: policy)
        let summary = try await evaluate("return document.querySelector('article.blocked summary').textContent;", controller) as? String
        #expect(summary == "Message masqué")
    }
}
