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
/// from the app, except for the YouTube player, which refuses to play without one (error 153, #752, LOT-071 R3
/// exception); navigation stays on the provider's host. A player that answers an error status, or cannot load, shows
/// "Vidéo indisponible" instead of a blank sheet.
struct VideoPlayerSheet: View {
    let embed: MessageEmbed
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var playerFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if let url = VideoPlayerSheet.playerURL(for: embed, failed: playerFailed) {
                    PlayerWebView(request: VideoPlayerSheet.playerRequest(for: url)) {
                        playerFailed = true
                    }
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

    /// Hosts of the YouTube embed player: the only ones that get a `Referer` (LOT-071 R3 exception, #752).
    static let refererHosts: Set<String> = allowedHosts(for: .youtube)

    /// The `Referer` that identifies the app to YouTube's embed player: `https://` and the lowercased app id (a development
    /// build sends its own id), as YouTube's "API Client Identity" rule asks
    /// (developers.google.com/youtube/terms/required-minimum-functionality).
    static func appReferer(bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> String {
        "https://\((bundleIdentifier ?? "hfrplus.red.super").lowercased())/"
    }

    /// The player request: `Referer` for a YouTube embed host only, none for any other host. WebKit does not resend it
    /// after a redirect, so a YouTube redirect would bring error 153 back.
    static func playerRequest(
        for url: URL, referer: String = appReferer(), refererHosts: Set<String> = refererHosts
    ) -> URLRequest {
        var request = URLRequest(url: url)
        if let host = url.host()?.lowercased(), refererHosts.contains(host) {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        return request
    }

    /// Whether the main frame's answer means the player cannot play (the Vimeo 401 of a removed video, a 5xx).
    static func isFailure(statusCode: Int) -> Bool { statusCode >= 400 }

    /// The original link the member posted, for "open in browser": `http` or `https` only, nothing else goes to the system.
    static func fallbackURL(for embed: MessageEmbed) -> URL? {
        guard let scheme = embed.sourceURL.scheme?.lowercased(), scheme == "https" || scheme == "http",
              embed.sourceURL.host() != nil else { return nil }
        return embed.sourceURL
    }

    /// The player URL to show, nil (the "Vidéo indisponible" view) once the player reported a failure.
    static func playerURL(for embed: MessageEmbed, failed: Bool) -> URL? {
        failed ? nil : playerURL(for: embed)
    }

    /// The embed URL when it is `https` on one of its provider's hosts; nil otherwise.
    static func playerURL(for embed: MessageEmbed) -> URL? {
        let url = embed.embedURL
        guard url.scheme?.lowercased() == "https", url.port == nil, url.user() == nil,
              let host = url.host()?.lowercased(), allowedHosts(for: embed.provider).contains(host) else { return nil }
        return url
    }
}

struct PlayerWebView: UIViewRepresentable {
    let request: URLRequest
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(host: request.url?.host()?.lowercased(), onFailure: onFailure) }

    func makeUIView(context: Context) -> WKWebView {
        Self.makeWebView(request: request, delegate: context.coordinator)
    }

    /// The player's web view, loading `request`; split out so tests drive the real thing.
    static func makeWebView(request: URLRequest, delegate: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsLinkPreview = false
        webView.navigationDelegate = delegate
        webView.load(request)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let host: String?
        let onFailure: () -> Void

        init(host: String?, onFailure: @escaping () -> Void) {
            self.host = host
            self.onFailure = onFailure
        }

        func webView(
            _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
        ) {
            if navigationResponse.isForMainFrame, let http = navigationResponse.response as? HTTPURLResponse,
               VideoPlayerSheet.isFailure(statusCode: http.statusCode) {
                decisionHandler(.cancel)
                onFailure()
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: any Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) {
            report(error)
        }

        /// A cancelled load is not a second failure: our own `.cancel` of an error status reaches here as
        /// `WebKitErrorDomain` 102 ("frame load interrupted"), a cancelled URL load as `NSURLErrorCancelled`.
        private func report(_ error: any Error) {
            let nsError = error as NSError
            let ours = nsError.domain == "WebKitErrorDomain" && nsError.code == 102
            if !ours && nsError.code != NSURLErrorCancelled { onFailure() }
        }

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
