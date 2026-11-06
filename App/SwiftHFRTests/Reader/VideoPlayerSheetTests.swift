import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// What the player sheet may load, and what its "open in browser" fallback may hand to the system.
struct VideoPlayerSheetTests {
    private func url(_ string: String) -> URL { URL(string: string) ?? URL(fileURLWithPath: "/") }

    private func embed(_ provider: EmbedProvider, source: String, player: String) -> MessageEmbed {
        MessageEmbed(provider: provider, sourceURL: url(source), embedURL: url(player))
    }

    @Test(arguments: [
        ("https://www.youtube.com/embed/a", EmbedProvider.youtube, true),
        ("http://player.vimeo.com/video/1", EmbedProvider.vimeo, false),
        ("https://www.youtube.com/embed/a", EmbedProvider.vimeo, false),
        ("https://streamable.com:8443/s/x", EmbedProvider.streamable, false)
    ])
    func thePlayerLoadsOnlyHttpsOnItsProviderHost(player: String, provider: EmbedProvider, loads: Bool) {
        let item = embed(provider, source: "https://example.com/v", player: player)
        #expect((VideoPlayerSheet.playerURL(for: item) != nil) == loads)
    }

    @Test func theBrowserFallbackIsTheOriginalLinkAndHttpOrHttpsOnly() {
        let web = embed(.youtube, source: "https://www.youtube.com/watch?v=a", player: "https://www.youtube.com/embed/a")
        #expect(VideoPlayerSheet.fallbackURL(for: web) == web.sourceURL)
        let plain = embed(.streamable, source: "http://streamable.com/x", player: "https://streamable.com/s/x")
        #expect(VideoPlayerSheet.fallbackURL(for: plain) == plain.sourceURL)
        let other = embed(.youtube, source: "tel:123", player: "https://www.youtube.com/embed/a")
        #expect(VideoPlayerSheet.fallbackURL(for: other) == nil)
        let local = embed(.youtube, source: "file:///etc/hosts", player: "https://www.youtube.com/embed/a")
        #expect(VideoPlayerSheet.fallbackURL(for: local) == nil)
    }
}
