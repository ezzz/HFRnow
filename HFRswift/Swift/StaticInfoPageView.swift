//
//  StaticInfoPageView.swift
//  HFRswift
//
//  SwiftUI migration for static HTML pages: credits + forum charter
//

import SwiftUI
import WebKit

enum StaticInfoPageKind {
    case credits
    case charter

    var title: String {
        switch self {
        case .credits:
            return "Crédits"
        case .charter:
            return "Charte du forum"
        }
    }

    var filename: String {
        switch self {
        case .credits:
            return "credits"
        case .charter:
            return "charte"
        }
    }
}

struct StaticInfoPageView: View {
    let kind: StaticInfoPageKind
    @State private var reloadToken = 0

    var body: some View {
        StaticHTMLWebView(filename: kind.filename, reloadToken: reloadToken)
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("kThemeChangedNotification"))) { _ in
                reloadToken += 1
            }
    }
}

private struct StaticHTMLWebView: UIViewRepresentable {
    let filename: String
    let reloadToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        let bgColor = ThemeColors.greyBackgroundColor()
        webView.backgroundColor = bgColor
        webView.scrollView.backgroundColor = bgColor
        context.coordinator.lastToken = reloadToken
        context.coordinator.loadHTML(filename: filename, into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let bgColor = ThemeColors.greyBackgroundColor()
        webView.backgroundColor = bgColor
        webView.scrollView.backgroundColor = bgColor

        guard context.coordinator.lastToken != reloadToken else { return }
        context.coordinator.lastToken = reloadToken
        context.coordinator.loadHTML(filename: filename, into: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastToken: Int = -1

        func loadHTML(filename: String, into webView: WKWebView) {
            guard let htmlPath = Bundle.main.path(forResource: filename, ofType: "html") else {
                webView.loadHTMLString("<html><body><p>Fichier introuvable</p></body></html>", baseURL: nil)
                return
            }

            let htmlURL = URL(fileURLWithPath: htmlPath)
            let baseURL = URL(fileURLWithPath: Bundle.main.bundlePath)
            var htmlString = (try? String(contentsOf: htmlURL, encoding: .utf8)) ?? ""

            // Keep legacy iOS token replacement behavior.
            htmlString = htmlString.replacingOccurrences(of: "%%iosversion%%", with: "ios7")
            htmlString = htmlString.replacingOccurrences(of: "%%iosversion%%", with: "")

            let cssString = currentCreditsCSS()
            htmlString = htmlString.replacingOccurrences(of: "</head>", with: "<style>\(cssString)</style></head>")
            let headerString = "<header><meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no'></header>"
            webView.loadHTMLString(headerString + htmlString, baseURL: baseURL)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let cssString = currentCreditsCSS()
            let escaped = cssString.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: " ")
            let javascript = "var style = document.createElement('style'); style.innerHTML = '\(escaped)'; document.head.appendChild(style);"
            webView.evaluateJavaScript(javascript, completionHandler: nil)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                if let appDelegate = HFRplusAppDelegate.shared() {
                    appDelegate.openURL(url.absoluteString)
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        private func currentCreditsCSS() -> String {
            guard let themeManager = ThemeManager.shared() else {
                return ""
            }
            return ThemeColors.creditsCss(themeManager.theme)
        }
    }
}

#Preview("Credits") {
    NavigationStack {
        StaticInfoPageView(kind: .credits)
    }
}

