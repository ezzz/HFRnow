import Foundation
import WebKit

/// Navigation: the web view never leaves the document, and a failed load of the shown one is retried, then reported (#566).
extension ReaderWebController: WKNavigationDelegate, WKUIDelegate {
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        let url = navigationAction.request.url
        if let url, let document, navigationAction.targetFrame?.isMainFrame == true,
           url == Self.pageURL(token: document.token), navigationAction.navigationType == .other {
            return decisionHandler(.allow)
        }
        decisionHandler(.cancel)
        if let url, navigationAction.navigationType == .linkActivated { events.link(url) }
    }

    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url { events.link(url) }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        contentProcessTerminated()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) {
        pageNavigationFailed(navigation, error: error)
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: any Error
    ) {
        pageNavigationFailed(navigation, error: error)
    }
}

/// Breaks the retain cycle configuration → handler → controller → web view → configuration.
@MainActor
final class ReaderSchemeProxy: NSObject, WKURLSchemeHandler {
    weak var owner: ReaderWebController?

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let owner else { return urlSchemeTask.didFailWithError(URLError(.cancelled)) }
        owner.start(urlSchemeTask)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        owner?.stop(urlSchemeTask)
    }
}

/// Same for the message channel, which `WKUserContentController` retains strongly.
@MainActor
final class ReaderMessageProxy: NSObject, WKScriptMessageHandlerWithReply {
    weak var owner: ReaderWebController?

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        (owner?.receive(message), nil)
    }
}
