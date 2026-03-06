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
    @ObservedObject private var appTheme = AppThemeStore.shared

    var body: some View {
        StaticHTMLWebView(
            filename: kind.filename,
            theme: appTheme.resolvedLegacyTheme,
            backgroundColor: appTheme.palette.staticPageBackgroundUIColor,
            themeRevision: appTheme.themeRevision
        )
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StaticHTMLWebView: UIViewRepresentable {
    let filename: String
    let theme: Theme
    let backgroundColor: UIColor
    let themeRevision: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = backgroundColor
        webView.scrollView.backgroundColor = backgroundColor
        context.coordinator.lastFilename = filename
        context.coordinator.lastThemeRevision = themeRevision
        context.coordinator.currentTheme = theme
        context.coordinator.loadHTML(filename: filename, theme: theme, into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.backgroundColor = backgroundColor
        webView.scrollView.backgroundColor = backgroundColor

        let coordinator = context.coordinator
        let didChangeFile = coordinator.lastFilename != filename
        let didChangeTheme = coordinator.currentTheme != theme
        let didChangeRevision = coordinator.lastThemeRevision != themeRevision

        coordinator.lastFilename = filename
        coordinator.lastThemeRevision = themeRevision
        coordinator.currentTheme = theme

        if didChangeFile {
            coordinator.loadHTML(filename: filename, theme: theme, into: webView)
        } else if didChangeTheme || didChangeRevision {
            coordinator.applyTheme(theme: theme, to: webView)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastFilename: String?
        var lastThemeRevision: Int = -1
        var currentTheme: Theme = ThemeLight

        func loadHTML(filename: String, theme: Theme, into webView: WKWebView) {
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

            let cssString = currentCreditsCSS(theme: theme)
            htmlString = htmlString.replacingOccurrences(
                of: "</head>",
                with: "<style id='hfr-static-theme-style'>\(cssString)</style></head>"
            )
            let headerString = "<header><meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no'></header>"
            webView.loadHTMLString(headerString + htmlString, baseURL: baseURL)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyTheme(theme: currentTheme, to: webView)
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

        func applyTheme(theme: Theme, to webView: WKWebView) {
            let cssString = currentCreditsCSS(theme: theme)
            let escaped = cssString.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: " ")
            let javascript = """
            (function() {
                var style = document.getElementById('hfr-static-theme-style');
                if (!style) {
                    style = document.createElement('style');
                    style.id = 'hfr-static-theme-style';
                    document.head.appendChild(style);
                }
                style.innerHTML = '\(escaped)';
            })();
            """
            webView.evaluateJavaScript(javascript, completionHandler: nil)
        }

        private func currentCreditsCSS(theme: Theme) -> String {
            ThemeUserColorStore.creditsCSS(forLegacyThemeValue: theme == ThemeDark ? 1 : 0)
        }
    }
}

#Preview("Credits") {
    NavigationStack {
        StaticInfoPageView(kind: .credits)
    }
}
