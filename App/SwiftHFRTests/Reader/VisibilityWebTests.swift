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
        _ messages: [ReaderMessage], policy: VisibilityPolicy, showsSignatures: Bool = false
    ) async -> (ReaderWebController, ReaderWebRecorder) {
        let (controller, recorder) = makeController(transport: imageTransport())
        let page = ReaderPage(topicID: readerTopic, title: "Titre", currentPage: 1, maxPage: 1, messages: messages)
        let options = ReaderRenderOptions(showsSignatures: showsSignatures, visibility: policy)
        controller.show(ReaderDocument(
            token: 1, html: TopicHTMLBuilder.document(for: page, token: 1, options: options), anchor: nil, keepsScrollPosition: false
        ))
        #expect(await until { recorder.ready == [1] })
        return (controller, recorder)
    }

    private func evaluate(_ script: String, _ controller: ReaderWebController) async throws -> Any? {
        try await evaluate(script, in: controller)
    }

    private func plain(
        _ author: String, _ number: Int, _ body: String = "<p>texte</p>", avatar: Bool = false
    ) -> ReaderMessage {
        ReaderMessage(
            numreponse: number, author: author, isDeleted: false, isContinuation: false,
            avatarURL: avatar ? url("https://forum-images.hardware.fr/avatars/a.png") : nil,
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
        // The header line is the control: a tap at its right end, away from the link and the arrow glyph, opens and closes it.
        let hit = """
            const quote = document.querySelector('table.quote-blocked');
            const rect = quote.querySelector('b.s1').getBoundingClientRect();
            const target = document.elementFromPoint(rect.right - 3, rect.top + rect.height / 2);
            const isHeader = target === quote.querySelector('b.s1');
            target.click();
            return [isHeader, quote.classList.contains('open')];
            """
        #expect(try await evaluate(hit, controller) as? [Bool] == [true, true])
        #expect(try await evaluate(hit, controller) as? [Bool] == [true, false])
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

    /// A quote of R26's shape (one row, one cell) with text outside any element after the header, which no selector can hide.
    @Test func looseTextOfACollapsedQuoteTakesNoSpaceAndTheCellKeepsItsPadding() async throws {
        let quote = "<table class=\"citation\"><tr class=\"none\"><td><b class=\"s1\">"
            + "<a class=\"Topic\" href=\"/x#t1\">user4 a écrit :</a></b>"
            + "<br /><br />texte libre <i>en italique</i><p>paragraphe</p> et la suite du texte libre</td></tr></table>"
        let message = ReaderMessage(
            numreponse: 1, author: "auteur", isDeleted: false, isContinuation: false, avatarURL: nil, dateText: "27-10-2026 10:00:00",
            editNote: nil, quotedByCount: nil, content: MessageContent(html: quote), quotes: [MessageQuote(author: "user4", depth: 1)]
        )
        let (controller, _) = await show([message], policy: VisibilityPolicy(blocklist: ["user4"]))
        let measure = """
            const cell = document.querySelector('table.quote-blocked td');
            const header = cell.querySelector('b.s1');
            const padding = parseFloat(getComputedStyle(cell).paddingTop);
            return [cell.getBoundingClientRect().height - header.getBoundingClientRect().height - 2 * padding, padding,
                    header.getBoundingClientRect().top - cell.getBoundingClientRect().top];
            """
        let collapsed = try #require(try await evaluate(measure, controller) as? [Double])
        #expect(abs(collapsed[0]) < 2) // nothing but the header and the padding: the loose text takes no line
        #expect(collapsed[1] > 4)
        _ = try await evaluate("document.querySelector('table.quote-blocked b.s1').click(); return true;", controller)
        let open = try #require(try await evaluate(measure, controller) as? [Double])
        #expect(open[0] > 20) // the loose text and the paragraph are there again
        // No jump: same padding, and the header stays where it was.
        #expect(abs(open[1] - collapsed[1]) < 1)
        #expect(abs(open[2] - collapsed[2]) < 1)
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
            const mix = document.createElement('span');
            mix.style.backgroundColor = 'color-mix(in srgb, var(--action) 3%, transparent)';
            document.body.append(mix);
            const style = getComputedStyle(document.querySelector('table.quote-me'));
            return [style.backgroundColor === getComputedStyle(mix).backgroundColor, style.borderLeftWidth,
                    style.borderLeftColor, getComputedStyle(probe).color,
                    document.querySelector('table.quote-me p').checkVisibility()];
            """, controller
        ) as? [Any]
        #expect(quote?[0] as? Bool == true)
        #expect(quote?[1] as? String == "2px")
        #expect(quote?[2] as? String == quote?[3] as? String)
        #expect(quote?[4] as? Bool == true)
    }

    @Test func theQuoteOfAnAllowlistedAuthorIsTintedWithTheLoveColour() async throws {
        let message = try Self.message(in: "R20-topic-p1-anon.html", quoting: "user4")
        let (controller, _) = await show([message], policy: VisibilityPolicy(allowlist: ["user4"]))
        let quote = try await evaluate(
            """
            const probe = document.createElement('span');
            probe.style.color = 'var(--love-border)';
            document.body.append(probe);
            const mix = document.createElement('span');
            mix.style.backgroundColor = 'color-mix(in srgb, var(--love) 30%, transparent)';
            document.body.append(mix);
            const style = getComputedStyle(document.querySelector('table.quote-allowed'));
            return [style.backgroundColor === getComputedStyle(mix).backgroundColor, style.borderLeftWidth,
                    style.borderLeftColor, getComputedStyle(probe).color,
                    document.querySelector('table.quote-allowed p').checkVisibility(),
                    document.querySelectorAll('table.quote-me, table.quote-blocked').length];
            """, controller
        ) as? [Any]
        #expect(quote?[0] as? Bool == true)
        #expect(quote?[1] as? String == "2px")
        #expect(quote?[2] as? String == quote?[3] as? String)
        #expect(quote?[4] as? Bool == true)
        #expect((quote?[5] as? NSNumber)?.intValue == 0)
    }

    @Test func aBlockedMessageIsOneClosedLineUntilItsSummaryIsTapped() async throws {
        let policy = VisibilityPolicy(blocklist: ["Troll"])
        let (controller, _) = await show([plain("Troll", 1, "<p>message masqué</p>"), plain("Inconnu", 2)], policy: policy)
        let hidden = "return document.querySelector('article.blocked .content').checkVisibility();"
        #expect(try await evaluate(hidden, controller) as? Bool == false)
        let summary = try await evaluate("return document.querySelector('article.blocked summary').textContent;", controller) as? String
        #expect(summary == "TrollMessage masqué")
        _ = try await evaluate("document.querySelector('article.blocked summary').click(); return true;", controller)
        #expect(try await evaluate(hidden, controller) as? Bool == true)
        #expect((try await evaluate("return document.querySelectorAll('details').length;", controller) as? NSNumber)?.intValue == 1)
    }

    @Test func ownAndAllowlistedMessagesAreTintedBarredAndRingedWithTheirColours() async throws {
        let policy = VisibilityPolicy(ownPseudo: "moi", allowlist: ["Ami"])
        let (controller, _) = await show(
            [plain("moi", 2, avatar: true), plain("Ami", 3, avatar: true), plain("Inconnu", 4)], policy: policy
        )
        #expect(await settled(controller))
        let tints = try await evaluate(
            """
            const probe = (value) => { const span = document.createElement('span'); span.style.color = value;
              document.body.append(span); return getComputedStyle(span).color; };
            const mixed = (name, percent) => { const span = document.createElement('span');
              span.style.backgroundColor = `color-mix(in srgb, var(${name}) ${percent}%, transparent)`;
              document.body.append(span); return getComputedStyle(span).backgroundColor; };
            const style = (selector, part) => getComputedStyle(document.querySelector('article' + selector + ' ' + part));
            return {
              actionColor: probe('var(--action)'), loveBorder: probe('var(--love-border)'),
              meContent: [style('.me', '.content').backgroundColor === mixed('--action', 3), style('.me', '.content').borderLeftColor],
              meHeader: [style('.me', '.header').borderLeftWidth, style('.me', '.header').borderLeftColor],
              meAvatar: [style('.me', '.avatar').borderLeftWidth, style('.me', '.avatar').borderLeftColor],
              loveAvatar: [style('.whitelist', '.avatar').borderLeftWidth, style('.whitelist', '.avatar').borderLeftColor],
              loveContent: [style('.whitelist', '.content').backgroundColor === mixed('--love', 40),
                style('.whitelist', '.content').borderLeftColor],
              loveHeader: [style('.whitelist', '.header').backgroundColor === mixed('--love', 40),
                style('.whitelist', '.header').borderLeftColor],
              meHeaderTint: style('.me', '.header').backgroundColor === mixed('--action', 3),
              plainContent: style(':not(.me):not(.whitelist):not(.blocked)', '.content').borderLeftWidth
            };
            """, controller
        ) as? [String: Any]
        let action = tints?["actionColor"] as? String
        let love = tints?["loveBorder"] as? String
        #expect((tints?["meContent"] as? [Any])?.first as? Bool == true)
        #expect((tints?["meContent"] as? [Any])?.last as? String == action)
        #expect(tints?["meHeaderTint"] as? Bool == true)
        #expect((tints?["meHeader"] as? [String]) == ["2px", action ?? ""])
        #expect((tints?["loveContent"] as? [Any])?.first as? Bool == true)
        #expect((tints?["loveContent"] as? [Any])?.last as? String == love)
        #expect((tints?["loveHeader"] as? [Any])?.first as? Bool == true)
        #expect((tints?["loveHeader"] as? [Any])?.last as? String == love)
        #expect((tints?["meAvatar"] as? [String]) == ["2px", action ?? ""])
        #expect((tints?["loveAvatar"] as? [String]) == ["2px", love ?? ""])
        #expect(tints?["plainContent"] as? String == "0px")
    }

    @Test func anOpenedBlockedMessageKeepsItsMarginsAndItsBottomPadding() async throws {
        let policy = VisibilityPolicy(blocklist: ["Troll"])
        var message = plain("Troll", 1)
        message.editNote = "Troll le 27-10-2026"
        message.content.signatureHTML = "<i>signature</i>"
        let (controller, _) = await show([message], policy: policy, showsSignatures: true)
        _ = try await evaluate("document.querySelector('article.blocked summary').click(); return true;", controller)
        let layout = try await evaluate(
            """
            const open = document.querySelector('.blocked-post');
            const left = (element) => element.getBoundingClientRect().left - open.getBoundingClientRect().left;
            return [left(open.querySelector('.header')), left(open.querySelector('.content')),
                    left(open.querySelector('.trailer')), left(open.querySelector('.signature')),
                    parseFloat(getComputedStyle(open).paddingBottom)];
            """, controller
        ) as? [Double]
        let measured = try #require(layout)
        #expect(measured.prefix(4).allSatisfy { $0 > 8 })
        #expect(measured[4] > 4)
    }

    @Test func hidingThePseudoRemovesItFromTheCollapsedLine() async throws {
        var policy = VisibilityPolicy(blocklist: ["Troll"])
        policy.hidesBlockedPseudo = true
        let (controller, _) = await show([plain("Troll", 1)], policy: policy)
        let summary = try await evaluate("return document.querySelector('article.blocked summary').textContent;", controller) as? String
        #expect(summary == "Message masqué")
    }
}
