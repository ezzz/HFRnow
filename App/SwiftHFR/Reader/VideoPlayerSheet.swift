import HFRModels
import SwiftUI
import WebKit

// Port of HFRswift/Wrapped/LinkItem.m (iframe builder, :148-158) and Wrapped/ParseMessagesOperation.m (:238-300) @ 2440d79.
// Differences: no auto-loaded iframe, a placeholder opens this sheet on tap (GAP-058, LOT-071 D-071-2, LOT-108); the
// "open the link" fallback is new, on the original link (LOT-108).
/// The third-party video player, loaded only after the user tapped its placeholder (LOT-071 D-071-2).
///
/// It runs in its own web view, never in the reader's: the reader keeps content JavaScript off and allows no frame,
/// while a player needs the provider's scripts. The data store is non-persistent and the request carries no `Referer`
/// from the app; navigation stays on the provider's host.
struct VideoPlayerSheet: View {
    let embed: MessageEmbed
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Group {
                if let url = VideoPlayerSheet.playerURL(for: embed) {
                    PlayerWebView(url: url)
                } else {
                    ContentUnavailableView(
                        "Vidéo indisponible", systemImage: "play.slash",
                        description: Text("Le lecteur ne peut pas être chargé ici. Ouvrez le lien de la vidéo.")
                    )
                }
            }
            .navigationTitle("Vidéo \(TopicHTMLBuilder.providerName(embed.provider))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                if let link = VideoPlayerSheet.fallbackURL(for: embed) {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Ouvrir le lien", systemImage: "safari") { openURL(link) }
                    }
                }
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

    /// The original link the member posted, for "open in browser": `http` or `https` only, nothing else goes to the system.
    static func fallbackURL(for embed: MessageEmbed) -> URL? {
        guard let scheme = embed.sourceURL.scheme?.lowercased(), scheme == "https" || scheme == "http",
              embed.sourceURL.host() != nil else { return nil }
        return embed.sourceURL
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
