import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// The reader document: untrusted values escaped, content inserted as body markup only, nothing remote.
struct TopicHTMLBuilderTests {
    private func message(
        author: String = "auteur", content: MessageContent = MessageContent(html: "<p>Bonjour</p>"),
        continuation: Bool = false, editNote: String? = nil, quotedBy: Int? = nil, avatar: URL? = nil
    ) -> ReaderMessage {
        ReaderMessage(
            numreponse: 42, author: author, isDeleted: false, isContinuation: continuation, avatarURL: avatar,
            dateText: "27-10-2026 10:00:00", editNote: editNote, quotedByCount: quotedBy, content: content
        )
    }

    private func page(_ messages: [ReaderMessage], title: String = "Sujet") -> ReaderPage {
        ReaderPage(topicID: readerTopic, title: title, currentPage: 1, maxPage: 1, messages: messages)
    }

    @Test func injectedValuesAreEscaped() {
        let hostile = "<script>alert(1)</script>\"' onmouseover=x"
        let html = TopicHTMLBuilder.document(
            for: page([message(author: hostile, editNote: hostile)], title: hostile), token: 1
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
        let html = TopicHTMLBuilder.document(
            for: page([message(editNote: "auteur le 27-10-2026", quotedBy: 3, avatar: url("https://forum-images.hardware.fr/a.png"))]),
            token: 1
        )
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
}
