import Foundation
import UIKit
import WebKit

/// Owns the reader's `WKWebView` and enforces what the page may do (LOT-083):
///
/// - nothing remote: the page, its stylesheet and every image come from the app's `hfrreader:` scheme; the Content Security
///   Policy (header and `<meta>`) allows nothing else, and content JavaScript is off;
/// - the only script is `reader.js`, a user script in the app's own content world, which the page cannot reach;
/// - images go through policy C and the cookie-less client (`ReaderImageFetcher`), decided per URL here;
/// - the web view never navigates away: link taps are handed to the app, new windows are refused, link previews are off;
/// - the data store is non-persistent: no cookie, cache or storage outlives the reader.
@MainActor
final class ReaderWebController: NSObject {
    /// Callbacks to the reader screen.
    struct Events {
        /// The document `token` reached DOMContentLoaded and its images were routed.
        var ready: @MainActor (Int) -> Void = { _ in }
        /// The user tapped a link.
        var link: @MainActor (URL) -> Void = { _ in }
        /// The user tapped the placeholder of video `index` of message `post` in document `token`.
        var video: @MainActor (_ post: Int, _ index: Int, _ token: Int) -> Void = { _, _, _ in }
    }

    /// The content world of `reader.js` and of its message channel; the page's own world cannot see either.
    static let world = WKContentWorld.world(name: "SwiftHFRReader")
    /// Name of the message channel (`window.webkit.messageHandlers.reader` in the reader's world).
    static let channel = "reader"
    /// Most images routed per document, so a hostile page cannot make the app hold an unbounded list.
    static let maximumImages = 5_000

    let webView: WKWebView
    var events = Events()

    private let imageFetcher: ReaderImageFetcher
    private let autoLoadsThirdPartyImages: @Sendable () -> Bool
    private var document: ReaderDocument?
    private var savedOffset: CGPoint?
    private var appliedScrollID: Int?
    private var running: [ObjectIdentifier: Task<Void, Never>] = [:]
    /// Image requests of the current document and whether the policy let them through (tests read it).
    private(set) var imageRequests: [(requested: URL, allowed: Bool)] = []

    /// Creates the web view. `autoLoadsThirdPartyImages` is read for every page and every image request.
    init(imageFetcher: ReaderImageFetcher, autoLoadsThirdPartyImages: @escaping @Sendable () -> Bool) {
        self.imageFetcher = imageFetcher
        self.autoLoadsThirdPartyImages = autoLoadsThirdPartyImages
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.dataDetectorTypes = []
        configuration.allowsInlineMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.upgradeKnownHostsToHTTPS = true
        let proxy = SchemeProxy()
        configuration.setURLSchemeHandler(proxy, forURLScheme: TopicHTMLBuilder.scheme)
        let messages = MessageProxy()
        configuration.userContentController.addScriptMessageHandler(messages, contentWorld: Self.world, name: Self.channel)
        if let script = Self.readerScript {
            configuration.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Self.world)
            )
        }
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        proxy.owner = self
        messages.owner = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsLinkPreview = false
        webView.isInspectable = false
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
    }

    /// Shows `document` unless it is already the one shown. Nothing happens for nil (the screen shows its own state).
    func show(_ document: ReaderDocument?) {
        guard let document, document.token != self.document?.token else { return }
        savedOffset = document.keepsScrollPosition ? webView.scrollView.contentOffset : nil
        self.document = document
        imageRequests.removeAll()
        webView.load(URLRequest(url: Self.pageURL(token: document.token)))
    }

    /// Scrolls to a message of the shown document, once per request.
    func apply(_ request: ScrollRequest?) {
        guard let request, request.id != appliedScrollID, request.token == document?.token else { return }
        appliedScrollID = request.id
        scroll(to: request.anchor)
    }

    /// Stops every image download in flight (the screen goes away).
    func stopLoading() {
        webView.stopLoading()
        for task in running.values { task.cancel() }
        running.removeAll()
    }

    static func pageURL(token: Int) -> URL {
        URL(string: "\(TopicHTMLBuilder.scheme)://page/\(token)") ?? URL(fileURLWithPath: "/")
    }

    private static let readerScript: String? = {
        guard let url = Bundle.main.url(forResource: "reader", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    private static let stylesheet: Data? = {
        guard let url = Bundle.main.url(forResource: "reader", withExtension: "css") else { return nil }
        return try? Data(contentsOf: url)
    }()

    private func scroll(to anchor: Int) {
        Task {
            _ = try? await webView.callAsyncJavaScript(
                "return window.hfrReader.scrollToPost(n);", arguments: ["n": anchor], in: nil, contentWorld: Self.world
            )
        }
    }

    // MARK: - Messages from reader.js

    fileprivate func receive(_ message: WKScriptMessage) -> Any? {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any],
              let type = body["type"] as? String, let token = (body["token"] as? NSNumber)?.intValue,
              let document, token == document.token else { return nil }
        switch type {
        case "images":
            let urls = (body["urls"] as? [Any] ?? []).prefix(Self.maximumImages)
            let auto = autoLoadsThirdPartyImages()
            return urls.map { value -> String in
                guard let text = value as? String, let url = URL(string: text) else { return ImageDecision.block.rawValue }
                return ImageDecision(origin: ImagePolicy.classify(url), autoLoadsThirdParty: auto).rawValue
            }
        case "ready":
            if let anchor = document.anchor {
                scroll(to: anchor)
            } else if let offset = savedOffset {
                webView.scrollView.setContentOffset(offset, animated: false)
            }
            savedOffset = nil
            events.ready(token)
            return nil
        case "video":
            if let post = (body["post"] as? NSNumber)?.intValue, let index = (body["index"] as? NSNumber)?.intValue {
                events.video(post, index, token)
            }
            return nil
        default:
            return nil
        }
    }

    // MARK: - hfrreader: scheme

    fileprivate func start(_ task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return fail(task) }
        switch url.host() {
        case "page":
            guard let document, url.lastPathComponent == String(document.token) else { return fail(task) }
            respond(task, url: url, data: Data(document.html.utf8), mimeType: "text/html", extra: [
                "Content-Security-Policy": TopicHTMLBuilder.contentSecurityPolicy, "Referrer-Policy": "no-referrer",
                "Cache-Control": "no-store"
            ])
        case "resource":
            guard url.path() == "/reader.css", let stylesheet = Self.stylesheet else { return fail(task) }
            respond(task, url: url, data: stylesheet, mimeType: "text/css")
        case "image":
            startImage(task, url: url)
        default:
            fail(task)
        }
    }

    fileprivate func stop(_ task: any WKURLSchemeTask) {
        let key = ObjectIdentifier(task)
        running[key]?.cancel()
        running[key] = nil
    }

    private func startImage(_ task: any WKURLSchemeTask, url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let source = items.first(where: { $0.name == "u" })?.value, let imageURL = URL(string: source) else {
            return fail(task)
        }
        let tapped = items.contains { $0.name == "tap" && $0.value == "1" }
        // The decision is taken again here: the page's own markup could name this scheme, and a tap only consents to a
        // third-party host, never to a blocked one.
        let decision = ImageDecision(
            origin: ImagePolicy.classify(imageURL), autoLoadsThirdParty: autoLoadsThirdPartyImages(), tapped: tapped
        )
        if imageRequests.count < Self.maximumImages { imageRequests.append((imageURL, decision == .load)) }
        guard decision == .load else { return fail(task) }
        let key = ObjectIdentifier(task)
        let fetcher = imageFetcher
        let allowsThirdParty = ImagePolicy.classify(imageURL) == .thirdParty
        running[key] = Task { [weak self] in
            let result: Result<(data: Data, mimeType: String), ReaderImageFetcher.Failure>
            do throws(ReaderImageFetcher.Failure) {
                result = .success(try await fetcher.image(at: imageURL, allowsThirdParty: allowsThirdParty))
            } catch {
                result = .failure(error)
            }
            guard let self, self.running.removeValue(forKey: key) != nil else { return }
            switch result {
            case .success(let image): self.respond(task, url: url, data: image.data, mimeType: image.mimeType)
            case .failure: self.fail(task)
            }
        }
    }

    private func respond(_ task: any WKURLSchemeTask, url: URL, data: Data, mimeType: String, extra: [String: String] = [:]) {
        // Images and the stylesheet stay in WebKit's memory cache (the non-persistent store keeps nothing on disk), so a
        // page full of the same smileys asks the client once per URL.
        var headers = ["Content-Type": mimeType, "Content-Length": String(data.count), "Cache-Control": "private, max-age=3600"]
        headers.merge(extra) { _, new in new }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)
            ?? URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: nil)
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func fail(_ task: any WKURLSchemeTask) {
        task.didFailWithError(URLError(.resourceUnavailable))
    }
}

// MARK: - Navigation: the web view never leaves the document

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
        // The content process died (memory pressure on a huge page): show the same document again.
        guard let document else { return }
        webView.load(URLRequest(url: Self.pageURL(token: document.token)))
    }
}

/// Breaks the retain cycle configuration → handler → controller → web view → configuration.
@MainActor
private final class SchemeProxy: NSObject, WKURLSchemeHandler {
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
private final class MessageProxy: NSObject, WKScriptMessageHandlerWithReply {
    weak var owner: ReaderWebController?

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        (owner?.receive(message), nil)
    }
}
