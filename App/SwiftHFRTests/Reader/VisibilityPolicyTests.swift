import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
import HFRStorage
@testable import SwiftHFR
import Testing

/// LOT-117: who is highlighted, collapsed or allowlisted in the reader, and how the document says so.
struct VisibilityPolicyTests {
    // MARK: Policy

    private let policy = VisibilityPolicy(
        ownPseudo: "Moi\u{200B}Même", blocklist: ["Troll", " Mauvais\u{200B}Coucheur "], allowlist: ["Ami", "troll"]
    )

    @Test func aMessageIsClassifiedModerationOwnBlockedAllowedOrNormal() {
        #expect(policy.post(by: "Modération") == .moderation)
        #expect(policy.post(by: "moimême") == .own)
        #expect(policy.post(by: "TROLL") == .blocked)
        #expect(policy.post(by: "mauvaiscoucheur") == .blocked)
        #expect(policy.post(by: "ami") == .allowlisted)
        #expect(policy.post(by: "Inconnu") == .normal)
    }

    @Test func aBlocklistedPseudoIsNeverAllowlistedAndTheModerationAndYouComeFirst() {
        // "troll" is on both lists: legacy's `isWL:` refuses a blocklisted pseudo (BlackList.m:119-122).
        #expect(policy.post(by: "troll") == .blocked)
        let onBoth = VisibilityPolicy(ownPseudo: "moi", blocklist: ["moi", "Modération"])
        #expect(onBoth.post(by: "Moi") == .own)
        #expect(onBoth.post(by: "Modération") == .moderation)
    }

    @Test func aQuoteIsClassifiedOfMeAllowedBlockedOrNormal() {
        #expect(policy.quote(by: "MOIMÊME") == .ofMe)
        #expect(policy.quote(by: "Ami") == .allowlisted)
        #expect(policy.quote(by: "Troll") == .blocked)
        #expect(policy.quote(by: "Inconnu") == .normal)
        #expect(policy.quote(by: nil) == .normal)
    }

    @Test func withoutOwnHighlightsKeepsTheListsOnly() {
        let other = policy.withoutOwnHighlights()
        #expect(other.post(by: "moimême") == .normal)
        #expect(other.quote(by: "moimême") == .normal)
        #expect(other.post(by: "troll") == .blocked)
        #expect(other.post(by: "ami") == .allowlisted)
    }

    @Test func anEmptyOrBlankPseudoNeverMatches() {
        let blank = VisibilityPolicy(ownPseudo: " \u{200B} ", blocklist: ["", "  "], allowlist: [""])
        #expect(blank.isNeutral)
        #expect(blank.post(by: "") == .normal)
        #expect(blank.quote(by: "") == .normal)
        #expect(VisibilityPolicy.none.isNeutral)
    }

    // MARK: Quote markup

    private func quote(_ author: String?, tag: String = "citation", inner: String = "") -> String {
        let header = author.map { "<a href=\"https://forum.hardware.fr/x#t1\" class=\"Topic\">\($0) a écrit :</a>" } ?? "Citation :"
        return "<table class=\"\(tag)\"><tr class=\"none\"><td><b class=\"s1\">\(header)</b></td></tr>"
            + "<tr class=\"cite_\"><td><div class=\"container\">corps\(inner)</div></td></tr></table>"
    }

    private func quotes(_ authors: [String?], depths: [Int]? = nil) -> [MessageQuote] {
        authors.enumerated().map { MessageQuote(author: $1, depth: depths?[$0] ?? 1) }
    }

    @Test func eachQuoteTableGetsItsOwnTokenInDocumentOrder() {
        let html = quote("Troll") + "<p>texte</p>" + quote(nil) + quote("Ami", tag: "oldcitation") + quote("moimême") + quote("Inconnu")
        let result = QuoteMarkup.annotate(html, quotes: quotes(["Troll", nil, "Ami", "moimême", "Inconnu"]), policy: policy)
        let classes = result.matches(of: /<table class="([^"]*)">/).map { String($0.1) }
        #expect(classes == ["citation quote-blocked", "citation", "oldcitation quote-allowed", "citation quote-me", "citation"])
    }

    @Test func aNestedQuoteIsClassedByItsOwnAuthor() {
        let html = quote("Troll", inner: quote("Ami") + quote(nil))
        let result = QuoteMarkup.annotate(html, quotes: quotes(["Troll", "Ami", nil], depths: [1, 2, 2]), policy: policy)
        let classes = result.matches(of: /<table class="([^"]*)">/).map { String($0.1) }
        #expect(classes == ["citation quote-blocked", "citation quote-allowed", "citation"])
    }

    @Test func hidingThePseudoAddsItsOwnToken() {
        let hiding = VisibilityPolicy(blocklist: ["Troll"], hidesBlockedPseudo: true)
        let result = QuoteMarkup.annotate(quote("Troll"), quotes: quotes(["Troll"]), policy: hiding)
        #expect(result.hasPrefix("<table class=\"citation quote-blocked quote-hide-author\">"))
    }

    @Test func otherTablesAreNotQuotesAndAHostileAttributeDoesNotFoolTheScan() {
        let spoiler = "<table class=\"spoiler\"><tr><td>secret</td></tr></table>"
        let code = "<table class=\"code\"><tr><td>x</td></tr></table>"
        let tricky = "<table title=\"a > b class=&quot;citation&quot;\" class=\"citation\"><tr><td>q</td></tr></table>"
        let result = QuoteMarkup.annotate(spoiler + code + tricky, quotes: quotes(["Troll"]), policy: policy)
        #expect(result.contains("<table class=\"spoiler\">"))
        #expect(result.contains("<table class=\"code\">"))
        #expect(result.contains("class=\"citation quote-blocked\"><tr><td>q</td>"))
    }

    @Test func aCountThatDiffersLeavesTheContentUntouched() {
        let html = quote("Troll") + quote("Troll")
        #expect(QuoteMarkup.annotate(html, quotes: quotes(["Troll"]), policy: policy) == html)
        #expect(QuoteMarkup.annotate(html, quotes: quotes(["Troll", "Troll", "Troll"]), policy: policy) == html)
        #expect(QuoteMarkup.annotate(html, quotes: [], policy: policy) == html)
        #expect(QuoteMarkup.annotate(html, quotes: quotes(["Troll", "Troll"]), policy: .none) == html)
    }

    // MARK: Document

    private func message(
        _ author: String, number: Int = 42, html: String = "<p>Bonjour</p>", quotes: [MessageQuote] = []
    ) -> ReaderMessage {
        ReaderMessage(
            numreponse: number, author: author, isDeleted: false, isContinuation: false, avatarURL: nil,
            dateText: "27-10-2026 10:00:00", editNote: nil, quotedByCount: nil, content: MessageContent(html: html), quotes: quotes
        )
    }

    private func page(_ messages: [ReaderMessage], topic: TopicID = readerTopic) -> ReaderPage {
        ReaderPage(topicID: topic, title: "Sujet", currentPage: 1, maxPage: 1, messages: messages)
    }

    private func html(_ messages: [ReaderMessage], policy: VisibilityPolicy, topic: TopicID = readerTopic, menus: Bool = false) -> String {
        TopicHTMLBuilder.document(
            for: page(messages, topic: topic), token: 1,
            options: ReaderRenderOptions(showsMessageMenus: menus, visibility: policy)
        )
    }

    private func articleClasses(_ document: String) -> [String] {
        document.matches(of: /<article class="([^"]*)"/).map { String($0.1) }
    }

    @Test func ownAllowlistedModerationAndBlockedMessagesCarryTheirClass() {
        let document = html(
            [message("MoiMême", number: 1), message("Ami", number: 2), message("Modération", number: 3),
             message("Troll", number: 4), message("Inconnu", number: 5)],
            policy: policy
        )
        #expect(articleClasses(document) == ["message me", "message whitelist", "message mode", "message blocked", "message"])
    }

    @Test func aBlockedMessageIsCollapsedButItsBodyAndMenuStayForRevealAndAlert() {
        let document = html([message("Troll", html: "<p>insulte</p>")], policy: policy, menus: true)
        #expect(document.contains("<details class=\"blocked-post\"><summary class=\"blocked-summary\">"))
        #expect(document.contains("<span class=\"blocked-author\">Troll</span>"))
        #expect(document.contains("<span class=\"blocked-note\">Message masqué</span></summary>"))
        // The body is inside the disclosure, with the message menu that offers "Alerter".
        let body = document.components(separatedBy: "</summary>").last ?? ""
        #expect(body.contains("<p>insulte</p>"))
        #expect(body.contains("data-menu=\"message\""))
        #expect(body.contains("</details>\n</article>"))
        #expect(document.contains("aria-label=\"Message de Troll, 27-10-2026 10:00:00\""))
    }

    @Test func hidingTheBlockedPseudoKeepsItOutOfTheCollapsedLine() {
        let hiding = VisibilityPolicy(blocklist: ["Troll"], hidesBlockedPseudo: true)
        let document = html([message("Troll")], policy: hiding)
        let collapsed = document.components(separatedBy: "</summary>").first ?? ""
        #expect(!collapsed.contains("Troll"))
        #expect(collapsed.contains("Message masqué"))
        #expect(document.contains("aria-label=\"Message masqué\""))
    }

    @Test func aPageWithoutPolicyIsUnchanged() {
        let document = html([message("Troll"), message("moimême", number: 43)], policy: .none)
        #expect(articleClasses(document) == ["message", "message"])
        #expect(!document.contains("<details"))
    }

    @Test func ownHighlightsAreOffOnPrivateMessagesButTheListsStayOn() {
        let privateTopic = TopicID(category: .privateMessages, topic: 77)
        let quoted = MessageQuote(author: "moimême", depth: 1)
        let document = html(
            [
                message("MoiMême", number: 1), message("Troll", number: 2),
                message("Ami", number: 3, html: quote("moimême"), quotes: [quoted])
            ],
            policy: policy, topic: privateTopic
        )
        #expect(articleClasses(document) == ["message", "message blocked", "message whitelist"])
        #expect(!document.contains("quote-me"))
    }

    @Test func aQuoteOfMeIsMarkedOnForumPagesOnly() {
        let quoted = MessageQuote(author: "moimême", depth: 1)
        let forum = html([message("Inconnu", html: quote("moimême"), quotes: [quoted])], policy: policy)
        #expect(forum.contains("<table class=\"citation quote-me\">"))
        #expect(articleClasses(forum) == ["message"])
    }

    // MARK: Settings

    @Test func theSettingsBuildThePolicyFromTheAccountTheListsAndTheHideSetting() {
        let store = InMemorySettingsStore()
        let lists = PseudoLists(blocklist: ["Troll"], allowlist: ["Ami"])
        let settings = ReaderSettings.live(store: store, isOnWiFi: { true }, pseudo: "Moi", pseudoLists: { lists })
        var visibility = settings.renderOptions().visibility
        #expect(visibility.post(by: "moi") == .own)
        #expect(visibility.post(by: "troll") == .blocked)
        #expect(visibility.post(by: "ami") == .allowlisted)
        #expect(!visibility.hidesBlockedPseudo)
        store.set(true, for: SettingKey.hideBlocklistedPosts)
        visibility = settings.renderOptions().visibility
        #expect(visibility.hidesBlockedPseudo)
    }

    @Test func loggedOutWithoutListsTheSettingsHighlightNothing() {
        let store = InMemorySettingsStore()
        let visibility = ReaderSettings.live(store: store, isOnWiFi: { true }).renderOptions().visibility
        #expect(visibility.post(by: "moi") == .normal)
        // Only the hide setting differs from `.none`, and it does nothing without a list.
        #expect(visibility.isNeutral)
    }

    // MARK: Real pages

    @Test(arguments: [
        "R20-topic-p1-anon.html", "R21-topic-p1-logged-in.html", "R22a-topic-middle-page-anon.html", "R26-topic-quotes-smileys-anon.html",
        "R27-topic-spoilers-anon.html", "R28-topic-images-videos-anon.html"
    ])
    func theQuoteTablesOfACapturedPageMatchTheTypedQuotes(capture: String) throws {
        let data = try LiveTopicPageSourceTests.capture(capture)
        let pageURL = url("https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm")
        let page = try LiveTopicPageSource.parse(
            String(decoding: data, as: UTF8.self), pageURL: pageURL, normalizer: LiveContentNormalizer()
        )
        let authored = page.messages.flatMap(\.quotes).compactMap(\.author)
        #expect(!authored.isEmpty)
        let everyone = VisibilityPolicy(blocklist: authored)
        var classed = 0
        for message in page.messages {
            let result = QuoteMarkup.annotate(message.content.html, quotes: message.quotes, policy: everyone)
            classed += result.matches(of: /quote-blocked/).count
        }
        // Every authored quote of the page was found by position: none fell back to "untouched" on a count mismatch.
        #expect(classed == authored.count)
    }
}
