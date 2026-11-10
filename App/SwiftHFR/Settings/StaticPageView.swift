import HFRStorage
import SwiftUI
import WebKit

// Port of HFRswift/Swift/StaticInfoPageView.swift (StaticInfoPageView) @ 87fe0d1c. Differences: JavaScript off, a link opens
// through the app's browser rule (GAP-151, LOT-120 spec).
/// A bundled static page (credits, charter) in a web view that runs no script and never leaves the page.
struct StaticPageView: View {
    let page: StaticPage
    /// Where "Navigateur par défaut" is read, at the time of a tap.
    var store: any SettingsStore = UserDefaultsSettingsStore()
    @State private var html: String
    @State private var external: StaticPageExternalLink?
    @Environment(\.openURL) private var openURL

    /// A view of `page`; its HTML is read once.
    init(page: StaticPage, store: any SettingsStore = UserDefaultsSettingsStore()) {
        self.page = page
        self.store = store
        _html = State(initialValue: page.html())
    }

    var body: some View {
        StaticPageWebView(html: html, onLink: open)
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $external) { link in SafariView(url: link.url).ignoresSafeArea() }
    }

    private func open(_ url: URL) {
        switch StaticPage.action(forLink: url, defaultBrowser: store.value(for: SettingKey.opensLinksInDefaultBrowser)) {
        case .inAppBrowser(let url): external = StaticPageExternalLink(url: url)
        case .defaultBrowser(let url): openURL(url)
        case .ignored: break
        }
    }
}

private struct StaticPageExternalLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Hosts the `WKWebView`: no page script, a transparent background over the app's, links handed to `onLink`.
struct StaticPageWebView: UIViewRepresentable {
    let html: String
    let onLink: (URL) -> Void

    /// The configuration of the page's web view: the page runs no script (the pages are static text).
    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        return configuration
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: Self.makeConfiguration())
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.onLink = onLink
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onLink = onLink
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var onLink: (URL) -> Void = { _ in }
        var loadedHTML: String?

        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated else { return decisionHandler(.allow) }
            decisionHandler(.cancel)
            if let url = navigationAction.request.url { onLink(url) }
        }
    }
}
