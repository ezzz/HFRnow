import Foundation
import HFRModels
@testable import SwiftHFR
import Testing
import UIKit

/// Secondary text on the tinted allowlist surfaces keeps WCAG AA (4.5:1) in the real reader (#644): the classic whitelist header's
/// date (`--love`) and the folded blocked quote header inside a whitelisted author's message (a tint over `--love`), modern and
/// classic, light and dark; and (#1358) the folded quote header of a moderation message and the date and folded quote header of a
/// continuation (75 % opacity); and (#1360) its ordinary quote header, signature, trailer and count bubble; and (#1362) every other
/// secondary text of a message on its own surface (allowlisted, moderation, own, plain): the ordinary, allowlisted and own quote headers
/// and an image link in the content. The background under the text is composited from the element's ancestors, as the engine paints it.
@MainActor
@Suite(.serialized)
struct ReaderAllowlistContrastWebTests: ReaderWebTesting {
    private func document(
        token: Int, style: ThemeStyle, author: String = "ami", isContinuation: Bool = false
    ) -> ReaderDocument {
        let html = """
            <p>texte</p><table class="citation"><tr class="none"><td><b class="s1">ami a écrit :</b><br><p>cité</p></td></tr></table>\
            <table class="citation quote-blocked"><tr class="none"><td><b class="s1">Citation masquée</b><br>\
            <p>cité</p></td></tr></table>\
            <table class="citation quote-allowed"><tr class="none"><td><b class="s1">ami a écrit :</b><br><p>cité</p></td></tr></table>\
            <table class="citation quote-me"><tr class="none"><td><b class="s1">moi a écrit :</b><br><p>cité</p></td></tr></table>\
            <p><span class="image-link">image.png</span></p>
            """
        let message = ReaderMessage(
            numreponse: 1, author: author, isDeleted: false, isContinuation: isContinuation, avatarURL: nil,
            dateText: "27-10-2026 10:01:00", editNote: "ami", quotedByCount: 2,
            content: MessageContent(html: html, signatureHTML: "<i>ma signature</i>")
        )
        let page = ReaderPage(topicID: readerTopic, title: "Titre", currentPage: 1, maxPage: 1, messages: [message])
        var options = ReaderRenderOptions(style: style, visibility: VisibilityPolicy(ownPseudo: "moi", allowlist: ["ami"]))
        options.showsSignatures = true
        return ReaderDocument(
            token: token, html: TopicHTMLBuilder.document(for: page, token: token, options: options),
            anchor: nil, keepsScrollPosition: false
        )
    }

    /// [header date contrast, folded quote header contrast, 1 when the header date is drawn in the page text colour, ordinary quote header
    /// contrast, signature contrast, trailer contrast, count bubble contrast, allowlisted quote header contrast, own quote header
    /// contrast, image link contrast] of the first message.
    private func probe(root rootSelector: String) -> String { """
        \(ContrastProbe.helpers)
        const root = document.querySelector('\(rootSelector)');
        if (!root) { return 'null'; }
        const textProbe = document.createElement('i');
        textProbe.style.color = 'var(--text)';
        document.body.appendChild(textProbe);
        const date = root.querySelector('.header .date');
        const dateIsText = getComputedStyle(date).color === getComputedStyle(textProbe).color;
        textProbe.remove();
        return JSON.stringify([
            ratio(date), ratio(root.querySelector('table.quote-blocked b.s1')), dateIsText ? 1 : 0,
            ratio(root.querySelector('table.citation:not(.quote-blocked) b.s1')), ratio(root.querySelector('.signature')),
            ratio(root.querySelector('.trailer')), ratio(root.querySelector('.trailer .quoted-bubble')),
            ratio(root.querySelector('table.quote-allowed b.s1')), ratio(root.querySelector('table.quote-me b.s1')),
            ratio(root.querySelector('.content .image-link'))
        ]);
        """ }

    private func read(
        style: UIUserInterfaceStyle, theme: ThemeStyle, token: Int,
        author: String = "ami", isContinuation: Bool = false, root: String = "article.message.whitelist"
    ) async -> [Double]? {
        let (controller, recorder) = makeController(transport: imageTransport())
        recorder.window?.overrideUserInterfaceStyle = style
        controller.show(document(token: token, style: theme, author: author, isContinuation: isContinuation))
        let script = probe(root: root)
        guard await until({ recorder.ready == [token] }) else { return nil }
        var seen: [Double]?
        _ = await until(async: {
            let json = (try? await self.evaluate(script, in: controller)) as? String ?? ""
            seen = try? JSONDecoder().decode([Double].self, from: Data(json.utf8))
            return seen != nil
        })
        return seen
    }

    private func check(style: UIUserInterfaceStyle, theme: ThemeStyle, token: Int) async {
        guard let seen = await read(style: style, theme: theme, token: token) else {
            Issue.record("the reader did not answer")
            return
        }
        #expect(seen[0] >= 4.5, "whitelist header date: \(seen[0])")
        #expect(seen[1] >= 4.5, "blocked quote header in a whitelisted message: \(seen[1])")
        // #1210: the classic header's date is drawn in the page text colour in dark; the light fix must not override it.
        if style == .dark, theme == .classic { #expect(seen[2] == 1, "classic dark keeps the date in the page text colour") }
    }

    @Test func inModernLightSecondaryTextHoldsAA() async { await check(style: .light, theme: .modern, token: 1) }
    @Test func inModernDarkSecondaryTextHoldsAA() async { await check(style: .dark, theme: .modern, token: 2) }
    @Test func inClassicLightSecondaryTextHoldsAA() async { await check(style: .light, theme: .classic, token: 3) }
    @Test func inClassicDarkSecondaryTextHoldsAA() async { await check(style: .dark, theme: .classic, token: 4) }

    /// #1358: the folded blocked quote's header in a moderation message (`--modo`), light and dark, both looks.
    private func checkModeration(style: UIUserInterfaceStyle, theme: ThemeStyle, token: Int) async {
        let seen = await read(
            style: style, theme: theme, token: token, author: VisibilityPolicy.moderationName, root: "article.message.mode"
        )
        guard let seen else { Issue.record("the reader did not answer"); return }
        #expect(seen[1] >= 4.5, "blocked quote header in a moderation message: \(seen[1])")
    }

    /// #1358: the date of an allowlisted continuation (75 % opacity), light and dark, both looks.
    private func checkContinuation(style: UIUserInterfaceStyle, theme: ThemeStyle, token: Int) async {
        let seen = await read(style: style, theme: theme, token: token, isContinuation: true)
        guard let seen else { Issue.record("the reader did not answer"); return }
        #expect(seen[0] >= 4.5, "allowlisted continuation date: \(seen[0])")
        #expect(seen[1] >= 4.5, "blocked quote header in an allowlisted continuation: \(seen[1])")
    }

    /// #1358: the same in a continuation of an author with no visibility rule (the date and the folded quote header).
    private func checkPlainContinuation(style: UIUserInterfaceStyle, theme: ThemeStyle, token: Int) async {
        let seen = await read(
            style: style, theme: theme, token: token, author: "inconnu", isContinuation: true, root: "article.message.continuation"
        )
        guard let seen else { Issue.record("the reader did not answer"); return }
        #expect(seen[0] >= 4.5, "continuation date: \(seen[0])")
        #expect(seen[1] >= 4.5, "blocked quote header in a continuation: \(seen[1])")
    }

    @Test func moderationQuoteHeaderInModernLightHoldsAA() async { await checkModeration(style: .light, theme: .modern, token: 5) }
    @Test func moderationQuoteHeaderInModernDarkHoldsAA() async { await checkModeration(style: .dark, theme: .modern, token: 6) }
    @Test func moderationQuoteHeaderInClassicLightHoldsAA() async { await checkModeration(style: .light, theme: .classic, token: 7) }
    @Test func moderationQuoteHeaderInClassicDarkHoldsAA() async { await checkModeration(style: .dark, theme: .classic, token: 8) }
    @Test func continuationDateInModernLightHoldsAA() async { await checkContinuation(style: .light, theme: .modern, token: 9) }
    @Test func continuationDateInModernDarkHoldsAA() async { await checkContinuation(style: .dark, theme: .modern, token: 10) }
    @Test func continuationDateInClassicLightHoldsAA() async { await checkContinuation(style: .light, theme: .classic, token: 11) }
    @Test func continuationDateInClassicDarkHoldsAA() async { await checkContinuation(style: .dark, theme: .classic, token: 12) }
    @Test func plainContinuationInModernLightHoldsAA() async { await checkPlainContinuation(style: .light, theme: .modern, token: 13) }
    @Test func plainContinuationInModernDarkHoldsAA() async { await checkPlainContinuation(style: .dark, theme: .modern, token: 14) }
    @Test func plainContinuationInClassicLightHoldsAA() async { await checkPlainContinuation(style: .light, theme: .classic, token: 15) }
    @Test func plainContinuationInClassicDarkHoldsAA() async { await checkPlainContinuation(style: .dark, theme: .classic, token: 16) }

    /// #1360: the other secondary texts of a continuation (75 % opacity): the ordinary quote header, the signature and the trailer, on
    /// the plain, allowlisted and moderation surfaces, light and dark, both looks.
    private enum Surface: String {
        case plain, allowlisted, moderation, own

        var author: String {
            switch self {
            case .plain: "inconnu"
            case .allowlisted: "ami"
            case .moderation: VisibilityPolicy.moderationName
            case .own: "moi"
            }
        }

        func root(continuation: Bool) -> String {
            switch self {
            case .plain: continuation ? "article.message.continuation" : "article.message"
            case .allowlisted: "article.message.whitelist"
            case .moderation: "article.message.mode"
            case .own: "article.message.me"
            }
        }
    }

    private func checkContinuationText(_ surface: Surface, _ style: UIUserInterfaceStyle, _ theme: ThemeStyle, _ token: Int) async {
        let seen = await read(
            style: style, theme: theme, token: token, author: surface.author, isContinuation: true, root: surface.root(continuation: true)
        )
        guard let seen, seen.count == 10 else { Issue.record("the reader did not answer"); return }
        #expect(seen[3] >= 4.5, "ordinary quote header in a \(surface.rawValue) continuation: \(seen[3])")
        #expect(seen[4] >= 4.5, "signature in a \(surface.rawValue) continuation: \(seen[4])")
        #expect(seen[5] >= 4.5, "trailer in a \(surface.rawValue) continuation: \(seen[5])")
        #expect(seen[6] >= 4.5, "count bubble in a \(surface.rawValue) continuation: \(seen[6])")
        #expect(seen[7] >= 4.5, "allowlisted quote header in a \(surface.rawValue) continuation: \(seen[7])")
        #expect(seen[8] >= 4.5, "own quote header in a \(surface.rawValue) continuation: \(seen[8])")
        #expect(seen[9] >= 4.5, "image link in a \(surface.rawValue) continuation: \(seen[9])")
    }

    @Test func plainContinuationTextInModernLight() async { await checkContinuationText(.plain, .light, .modern, 17) }
    @Test func plainContinuationTextInModernDark() async { await checkContinuationText(.plain, .dark, .modern, 18) }
    @Test func plainContinuationTextInClassicLight() async { await checkContinuationText(.plain, .light, .classic, 19) }
    @Test func plainContinuationTextInClassicDark() async { await checkContinuationText(.plain, .dark, .classic, 20) }
    @Test func allowlistedContinuationTextInModernLight() async { await checkContinuationText(.allowlisted, .light, .modern, 21) }
    @Test func allowlistedContinuationTextInModernDark() async { await checkContinuationText(.allowlisted, .dark, .modern, 22) }
    @Test func allowlistedContinuationTextInClassicLight() async { await checkContinuationText(.allowlisted, .light, .classic, 23) }
    @Test func allowlistedContinuationTextInClassicDark() async { await checkContinuationText(.allowlisted, .dark, .classic, 24) }
    @Test func moderationContinuationTextInModernLight() async { await checkContinuationText(.moderation, .light, .modern, 25) }
    @Test func moderationContinuationTextInModernDark() async { await checkContinuationText(.moderation, .dark, .modern, 26) }
    @Test func moderationContinuationTextInClassicLight() async { await checkContinuationText(.moderation, .light, .classic, 27) }
    @Test func moderationContinuationTextInClassicDark() async { await checkContinuationText(.moderation, .dark, .classic, 28) }

    /// #1362: every secondary text of a message that is not a continuation, on its own surface (the allowlist `--love`, the moderation
    /// `--modo`, the own-message tint, the plain page), light and dark, both looks.
    private static let surfaceTexts: [(Int, String)] = [
        (0, "header date"), (1, "folded quote header"), (3, "ordinary quote header"), (4, "signature"), (5, "trailer"),
        (6, "count bubble"), (7, "allowlisted quote header"), (8, "own quote header"), (9, "image link")
    ]

    private func checkSurfaceText(_ surface: Surface, _ style: UIUserInterfaceStyle, _ theme: ThemeStyle, _ token: Int) async {
        let seen = await read(style: style, theme: theme, token: token, author: surface.author, root: surface.root(continuation: false))
        guard let seen, seen.count == 10 else { Issue.record("the reader did not answer"); return }
        for (index, label) in Self.surfaceTexts {
            #expect(seen[index] >= 4.5, "\(label) in a \(surface.rawValue) message: \(seen[index])")
        }
    }

    @Test func allowlistedTextInModernLight() async { await checkSurfaceText(.allowlisted, .light, .modern, 29) }
    @Test func allowlistedTextInModernDark() async { await checkSurfaceText(.allowlisted, .dark, .modern, 30) }
    @Test func allowlistedTextInClassicLight() async { await checkSurfaceText(.allowlisted, .light, .classic, 31) }
    @Test func allowlistedTextInClassicDark() async { await checkSurfaceText(.allowlisted, .dark, .classic, 32) }
    @Test func moderationTextInModernLight() async { await checkSurfaceText(.moderation, .light, .modern, 33) }
    @Test func moderationTextInModernDark() async { await checkSurfaceText(.moderation, .dark, .modern, 34) }
    @Test func moderationTextInClassicLight() async { await checkSurfaceText(.moderation, .light, .classic, 35) }
    @Test func moderationTextInClassicDark() async { await checkSurfaceText(.moderation, .dark, .classic, 36) }
    @Test func ownTextInModernLight() async { await checkSurfaceText(.own, .light, .modern, 37) }
    @Test func ownTextInModernDark() async { await checkSurfaceText(.own, .dark, .modern, 38) }
    @Test func ownTextInClassicLight() async { await checkSurfaceText(.own, .light, .classic, 39) }
    @Test func ownTextInClassicDark() async { await checkSurfaceText(.own, .dark, .classic, 40) }
    @Test func plainTextInModernLight() async { await checkSurfaceText(.plain, .light, .modern, 41) }
    @Test func plainTextInModernDark() async { await checkSurfaceText(.plain, .dark, .modern, 42) }
    @Test func plainTextInClassicLight() async { await checkSurfaceText(.plain, .light, .classic, 43) }
    @Test func plainTextInClassicDark() async { await checkSurfaceText(.plain, .dark, .classic, 44) }
}
