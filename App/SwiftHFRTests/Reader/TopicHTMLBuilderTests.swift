import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// The reader document: untrusted values escaped, content inserted as body markup only, nothing remote.
struct TopicHTMLBuilderTests {
    private func message(
        author: String = "auteur", content: MessageContent = MessageContent(html: "<p>Bonjour</p>"), continuation: Bool = false
    ) -> ReaderMessage {
        ReaderMessage(
            numreponse: 42, author: author, isDeleted: false, isContinuation: continuation, avatarURL: nil,
            dateText: "27-10-2026 10:00:00", editNote: nil, quotedByCount: nil, content: content
        )
    }

    private func edited(_ message: ReaderMessage, note: String) -> ReaderMessage {
        var message = message
        message.editNote = note
        return message
    }

    private func page(_ messages: [ReaderMessage], title: String = "Sujet") -> ReaderPage {
        ReaderPage(topicID: readerTopic, title: title, currentPage: 1, maxPage: 1, messages: messages)
    }

    @Test func theFlagMessageIsFollowedByTheLegacySeparatorUnlessLast() {
        let loaded = readerPage(page: 3)
        let flagged = TopicHTMLBuilder.document(for: loaded, token: 1, separatorAfter: 300)
        #expect(flagged.components(separatedBy: "<div class=\"separator1\"></div>").count == 2)
        let line = flagged.range(of: "<div class=\"separator1\">")?.lowerBound
        #expect(line.map { flagged[..<$0].contains("id=\"t300\"") && !flagged[..<$0].contains("id=\"t301\"") } == true)
        #expect(!TopicHTMLBuilder.document(for: loaded, token: 1, separatorAfter: 301).contains("separator1"))
        #expect(!TopicHTMLBuilder.document(for: loaded, token: 1).contains("separator1"))
    }

    @Test func injectedValuesAreEscaped() {
        let hostile = "<script>alert(1)</script>\"' onmouseover=x"
        let html = TopicHTMLBuilder.document(
            for: page([edited(message(author: hostile), note: hostile)], title: hostile), token: 1
        )
        #expect(!html.contains("<script"))
        #expect(!html.contains("\"' onmouseover"))
        #expect(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;&quot;&#39; onmouseover=x"))
    }

    @Test func contentIsInsertedAsBodyMarkup() {
        let content = MessageContent(html: "<p>Un <b>gras</b> &amp; <a href=\"https://example.com/\">lien</a></p>")
        let html = TopicHTMLBuilder.document(for: page([message(content: content)]), token: 1)
        #expect(html.contains("<div class=\"content\"><p>Un <b>gras</b> &amp; <a href=\"https://example.com/\">lien</a></p></div>"))
        let head = html.components(separatedBy: "<body").first ?? ""
        #expect(!head.contains("gras"))
    }

    @Test func theDocumentAllowsNothingRemote() {
        let html = TopicHTMLBuilder.document(for: page([message()]), token: 7)
        let csp = TopicHTMLBuilder.contentSecurityPolicy
        #expect(csp.contains("default-src 'none'"))
        #expect(csp.contains("script-src 'none'"))
        #expect(csp.contains("img-src hfrreader:;"))
        #expect(!csp.contains("http"))
        #expect(html.contains("<meta http-equiv=\"Content-Security-Policy\" content=\"\(csp)\">"))
        #expect(html.contains("<meta name=\"referrer\" content=\"no-referrer\">"))
        #expect(html.contains("data-token=\"7\""))
        #expect(!html.contains("<script"))
        #expect(html.firstMatch(of: /\son[a-z]+\s*=/) == nil)
    }

    @Test func signaturesFollowTheSetting() {
        let content = MessageContent(html: "<p>corps</p>", signatureHTML: "<i>ma signature</i>")
        let hidden = TopicHTMLBuilder.document(for: page([message(content: content)]), token: 1)
        #expect(!hidden.contains("ma signature"))
        let shown = TopicHTMLBuilder.document(
            for: page([message(content: content)]), token: 1, options: ReaderRenderOptions(showsSignatures: true)
        )
        #expect(shown.contains("<div class=\"signature\"><i>ma signature</i></div>"))
    }

    @Test func onlyTheOriginalMessageCarriesTheAnchor() {
        let html = TopicHTMLBuilder.document(for: page([message(continuation: true), message()]), token: 1)
        #expect(html.components(separatedBy: "id=\"t42\"").count == 2)
        #expect(html.contains("Reprise du message précédent"))
    }

    @Test func trailersAndAvatar() {
        var trailed = edited(message(), note: "auteur le 27-10-2026")
        trailed.quotedByCount = 3
        trailed.avatarURL = url("https://forum-images.hardware.fr/a.png")
        let html = TopicHTMLBuilder.document(for: page([trailed]), token: 1)
        #expect(html.contains("Message édité par auteur le 27-10-2026"))
        #expect(html.contains("Message cité 3 fois"))
        #expect(html.contains("<img class=\"avatar\" src=\"https://forum-images.hardware.fr/a.png\" alt=\"\">"))
    }

    @Test func aVideoIsAPlaceholderThatNamesNoProviderURL() {
        let embed = MessageEmbed(
            provider: .youtube, sourceURL: url("https://www.youtube.com/watch?v=abc"),
            embedURL: url("https://www.youtube.com/embed/abc")
        )
        let html = TopicHTMLBuilder.document(
            for: page([message(content: MessageContent(html: "<p>v</p>", embeds: [embed]))]), token: 1
        )
        #expect(html.contains("<button type=\"button\" class=\"video\" data-post=\"42\" data-video=\"0\""))
        #expect(!html.contains("youtube.com/embed"))
        #expect(!html.contains("<iframe"))
    }

    // MARK: Avatar and monogram (issue #595)

    @Test func aMemberWithoutAvatarGetsAMonogramNotAnImage() {
        var mute = message()
        mute.author = "Jean-Claude"
        let html = TopicHTMLBuilder.document(for: page([mute]), token: 1)
        #expect(html.contains("class=\"avatar avatar-default\""))
        #expect(html.contains(">JC</span>"))
        #expect(!html.contains("<img class=\"avatar\""))
        #expect(!html.contains("has-image"))
        // Local markup only: no URL, no script, so the CSP has nothing to allow.
        #expect(!html.contains("<script"))
    }

    @Test func theMonogramColoursAreTheMPListsAndStable() {
        var mute = message()
        mute.author = "auteur"
        let mark = Monogram(pseudo: "auteur")
        let expected = "--mono-light:\(Monogram.hex(mark.background(dark: false)));--mono-dark:\(Monogram.hex(mark.background(dark: true)))"
        let first = TopicHTMLBuilder.document(for: page([mute]), token: 1)
        #expect(first.contains(expected))
        #expect(first.contains("style=\"--mono-light:#"))
        #expect(first == TopicHTMLBuilder.document(for: page([mute]), token: 1))
    }

    @Test func thePseudoIsEscapedInTheAvatarLabelAndTheMonogram() {
        var odd = message()
        odd.author = "a\"><img src=x>"
        let html = TopicHTMLBuilder.avatar(of: odd, opensMenu: true)
        #expect(!html.contains("<img src=x>"))
        #expect(html.contains("aria-label=\"Menu de a&quot;&gt;&lt;img src=x&gt;\""))
    }

    @Test func theAvatarIsTheAuthorMenuButtonWithOrWithoutPicture() {
        let options = ReaderRenderOptions(showsAuthorMenus: true)
        var withImage = message()
        withImage.avatarURL = url("https://forum-images.hardware.fr/a.png")
        let withHTML = TopicHTMLBuilder.document(for: page([withImage]), token: 1, options: options)
        #expect(withHTML.contains("class=\"avatar-wrap has-image menu-avatar\" data-menu=\"avatar\" data-post=\"42\""))
        #expect(withHTML.contains("<button type=\"button\" class=\"avatar-wrap"))
        #expect(withHTML.contains("<img class=\"avatar\" src=\"https://forum-images.hardware.fr/a.png\" alt=\"\"></button>"))
        let without = TopicHTMLBuilder.document(for: page([message()]), token: 1, options: options)
        #expect(without.contains("class=\"avatar-wrap menu-avatar\" data-menu=\"avatar\" data-post=\"42\""))
        // Menus off: the avatar is plain markup.
        let off = TopicHTMLBuilder.document(for: page([withImage]), token: 1)
        #expect(!off.contains("data-menu") && off.contains("<span class=\"avatar-wrap has-image\">"))
    }
}

/// The message menu buttons of LOT-087.
struct TopicHTMLBuilderMenuTests {
    private func page(continuation: Bool = false) -> ReaderPage {
        ReaderPage(
            topicID: readerTopic, title: "Sujet", currentPage: 2, maxPage: 2,
            messages: [
                ReaderMessage(
                    numreponse: 42, author: "<b>x</b>", isDeleted: false, isContinuation: continuation, avatarURL: nil,
                    dateText: "27-10-2026 10:00:00", editNote: nil, quotedByCount: nil, content: MessageContent(html: "<p>a</p>")
                )
            ]
        )
    }

    @Test func buttonsAreOffByDefault() {
        let html = TopicHTMLBuilder.document(for: page(), token: 1)
        #expect(!html.contains("data-menu"))
        #expect(html.contains("<span class=\"author\">"))
    }

    @Test func eachMessageGetsAMenuButtonAndATappableAuthorWithEscapedText() {
        let options = ReaderRenderOptions(showsMessageMenus: true, showsAuthorMenus: true)
        let html = TopicHTMLBuilder.document(for: page(), token: 1, options: options)
        #expect(html.contains("data-menu=\"message\" data-post=\"42\""))
        #expect(html.contains("data-menu=\"avatar\" data-post=\"42\""))
        #expect(html.contains("&lt;b&gt;x&lt;/b&gt;"))
        #expect(!html.contains("<b>x</b>"))
    }

    @Test func theContinuationCopyHasNoMenu() {
        let options = ReaderRenderOptions(showsMessageMenus: true, showsAuthorMenus: true)
        let html = TopicHTMLBuilder.document(for: page(continuation: true), token: 1, options: options)
        #expect(!html.contains("data-menu"))
    }

    @Test func theTwoMenusAreDrawnIndependently() {
        let messageOptions = ReaderRenderOptions(showsMessageMenus: true)
        let messageOnly = TopicHTMLBuilder.document(for: page(), token: 1, options: messageOptions)
        #expect(messageOnly.contains("data-menu=\"message\"") && !messageOnly.contains("data-menu=\"avatar\""))
        #expect(messageOnly.contains("<span class=\"author\">"))
        let authorOnly = TopicHTMLBuilder.document(for: page(), token: 1, options: ReaderRenderOptions(showsAuthorMenus: true))
        #expect(authorOnly.contains("data-menu=\"avatar\"") && !authorOnly.contains("data-menu=\"message\""))
    }
}
