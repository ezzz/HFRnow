import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// The « Vidéos » setting (#691): the player on a tap (default) or the plain link, through the settings, the model and the page.
@MainActor
struct ReaderVideosModeTests {
    private let link = "https://www.youtube.com/watch?v=abc"
    private let player = "https://www.youtube.com/embed/abc"

    private func document(embedding: Bool) -> String {
        let embed = MessageEmbed(
            provider: .youtube, sourceURL: url(link), embedURL: url(player)
        )
        let content = MessageContent(html: "<p><a class=\"cLink\" href=\"\(link)\">\(link)</a></p>", embeds: [embed])
        var page = readerPage(page: 1)
        page.messages[0].content = content
        return TopicHTMLBuilder.document(for: page, token: 1, options: ReaderRenderOptions(embedsVideos: embedding))
    }

    @Test func embeddedIsTheDefaultOfTheRenderOptions() {
        #expect(ReaderRenderOptions().embedsVideos)
    }

    @Test func integratedKeepsThePlaceholderAndTheLinkOnlyAsALink() {
        let html = document(embedding: true)
        #expect(html.contains("class=\"video\""))
        #expect(html.contains("href=\"\(link)\""))
        #expect(!html.contains("<iframe") && !html.contains("youtube.com/embed"), "no provider before a tap")
    }

    @Test func linkLeavesTheVideoALinkWithNoPlaceholder() {
        let html = document(embedding: false)
        #expect(!html.contains("class=\"video\""))
        #expect(!html.contains("Vidéo YouTube"))
        #expect(html.contains("href=\"\(link)\""), "the link stays a normal link")
        #expect(!html.contains("<iframe") && !html.contains("youtube.com/embed"))
    }

    @Test(arguments: [("yes", true), ("both", true), ("no", false), ("sometimes", true)])
    func theReaderReadsTheLegacyKey(raw: String, embeds: Bool) {
        let store = InMemorySettingsStore(["embedded_videos": .string(raw)])
        let settings = ReaderSettings.live(store: store, isOnWiFi: { true })
        #expect(settings.renderOptions().embedsVideos == embeds)
    }

    @Test func aFreshStoreEmbedsVideos() {
        let settings = ReaderSettings.live(store: InMemorySettingsStore(), isOnWiFi: { true })
        #expect(settings.renderOptions().embedsVideos)
    }

    @Test func theSettingsModelShowsTheChoiceAndWritesTheLegacyKey() {
        let store = InMemorySettingsStore()
        let model = TopicsSettingsModel(store: store)
        #expect(model.embedsVideos)
        #expect(store.rawValue(forKey: "embedded_videos") == nil, "creating writes nothing")
        model.embedsVideos = false
        #expect(store.rawValue(forKey: "embedded_videos") == .string("no"))
        model.embedsVideos = true
        #expect(store.rawValue(forKey: "embedded_videos") == .string("yes"))
    }

    @Test func choosingIntegratedAgainKeepsALegacyBoth() {
        let store = InMemorySettingsStore(["embedded_videos": .string("both")])
        let model = TopicsSettingsModel(store: store)
        #expect(model.embedsVideos)
        model.embedsVideos = true
        #expect(store.rawValue(forKey: "embedded_videos") == .string("both"))
    }
}
