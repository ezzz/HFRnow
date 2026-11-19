import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// #1189: a private conversation opened by a followed link offers what the same conversation opened from Messages offers
/// (LOT-128): the page's own answer link, and the reader's composer.
@MainActor
struct LinkedPrivateConversationTests {
    /// `RA1` is a captured MP thread page with its `#repondre_form` (`cat=prive&post=3207033`).
    private static func mpPage() throws -> ReaderPage {
        let html = try #require(String(data: try LiveTopicPageSourceTests.capture("RA1-mp-thread-after-create.html"), encoding: .utf8))
        let pageURL = url("https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=prive&post=3207033&page=1")
        return try LiveTopicPageSource.parse(html, pageURL: pageURL, normalizer: LiveTopicPageSourceTests.MarkingNormalizer())
    }

    /// Followed from a topic, the conversation loads its page and has a reply target on its own topic: the reply button,
    /// quote and the message actions only wait for the composer the view hands it.
    @Test func aLinkedPrivateConversationHasItsOwnReplyTarget() async throws {
        let conversation = try Self.mpPage()
        let pages = FakeTopicPages { target in
            if case .topic(let topic) = target.source, topic.category == .privateMessages { return conversation }
            return readerPage(page: target.page)
        }
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic)), title: "Sujet", source: pages)
        await reader.onAppear()
        let link = url("https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=prive&post=3207033&page=1")
        guard case .reader(let target) = reader.action(forLink: link, defaultBrowser: false) else {
            Issue.record("A private conversation link opens in the app")
            return
        }
        reader.follow(target)
        let linked = try #require(reader.linkedReader)
        await linked.onAppear()
        #expect(linked.isPrivateConversation)
        let reply = try #require(linked.replyTarget)
        #expect(reply.topic == conversation.topicID)
        #expect(reply.topic.category == .privateMessages)
    }

    /// The view hands a linked reader its own composer, a private conversation included: no branch on the conversation kind
    /// is left at the destination (the reason it had, "no composer in Messages", ended with LOT-128).
    @Test func theLinkedReaderGetsTheComposerWhateverItShows() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "SwiftHFR/Reader/TopicReaderView.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        #expect(text.contains("TopicReaderView(model: linked.model, services: services, composer: composer)"))
        #expect(!text.contains("isPrivateConversation ? nil"))
    }
}
