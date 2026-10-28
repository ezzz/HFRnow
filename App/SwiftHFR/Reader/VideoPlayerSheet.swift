import HFRModels
import SwiftUI
import WebKit

/// The third-party video player, loaded only after the user tapped its placeholder (LOT-071 D-071-2).
///
/// It runs in its own web view, never in the reader's: the reader keeps content JavaScript off and allows no frame,
/// while a player needs the provider's scripts. The data store is non-persistent and the request carries no `Referer`
/// from the app; navigation stays on the provider's host.
struct VideoPlayerSheet: View {
    let embed: MessageEmbed
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let url = VideoPlayerSheet.playerURL(for: embed) {
                    PlayerWebView(url: url)
                } else {
                    ContentUnavailableView("Vidéo indisponible", systemImage: "play.slash")
                }
            }
            .navigationTitle("Vidéo \(TopicHTMLBuilder.providerName(embed.provider))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
        }
    }

    /// Hosts each provider's player may use (the parser builds the embed URL from the video id, ADR 0006 amendment 1).
    static func allowedHosts(for provider: EmbedProvider) -> Set<String> {
        switch provider {
        case .youtube: ["www.youtube.com", "youtube.com", "www.youtube-nocookie.com"]
        case .vimeo: ["player.vimeo.com"]
        case .streamable: ["streamable.com"]
        }
    }

    /// The embed URL when it is `https` on one of its provider's hosts; nil otherwise.
    static func playerURL(for embed: MessageEmbed) -> URL? {
        let url = embed.embedURL
        guard url.scheme?.lowercased() == "https", url.port == nil, url.user() == nil,
              let host = url.host()?.lowercased(), allowedHosts(for: embed.provider).contains(host) else { return nil }
        return url
    }
}

private struct PlayerWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(host: url.host()?.lowercased()) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsLinkPreview = false
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let host: String?

        init(host: String?) { self.host = host }

        /// The main frame stays on the player's host; the player's own frames may load what they need.
        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            let isMain = navigationAction.targetFrame?.isMainFrame ?? true
            let sameHost = navigationAction.request.url?.host()?.lowercased() == host
            decisionHandler(!isMain || sameHost ? .allow : .cancel)
        }
    }
}
