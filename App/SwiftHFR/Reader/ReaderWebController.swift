import Foundation
import UIKit
import WebKit

// Port of HFRswift/Swift/MessagesView.swift (WebView, MessageWebView, WebView.Coordinator) @ 2440d79. Differences: no page script,
// strict CSP, everything served by the app's `hfrreader:` scheme, images through policy C and the cookie-less client (GAP-050, 056).
/// Owns the reader's `WKWebView` and enforces what the page may do (LOT-083):
///
/// - nothing remote: the page, its stylesheet and every image come from the app's `hfrreader:` scheme; the Content Security
///   Policy (header and `<meta>`) allows nothing else, and content JavaScript is off;
/// - the only script is `reader.js`, a user script in the app's own content world, which the page cannot reach;
/// - images go through policy C and the cookie-less client (`ReaderImageFetcher`), decided per URL here;
/// - the web view never navigates away: link taps are handed to the app, new windows are refused, and a link's long-press
///   menu is the app's own, without preview;
/// - the data store is non-persistent: no cookie, cache or storage outlives the reader.
@MainActor
final class ReaderWebController: NSObject {
    /// Callbacks to the reader screen.
    struct Events {
        /// The document `token` reached DOMContentLoaded and its images were routed.
        var ready: @MainActor (Int) -> Void = { _ in }
        /// The document `token` could not be shown: its navigation failed twice (issue #566).
        var failed: @MainActor (Int) -> Void = { _ in }
        /// The user tapped a link.
        var link: @MainActor (URL) -> Void = { _ in }
        /// The user tapped the placeholder of video `index` of message `post` in document `token`.
        var video: @MainActor (_ post: Int, _ index: Int, _ token: Int) -> Void = { _, _, _ in }
        /// Scrolling paused with message `post` topmost in document `token` (LOT-111, recorded as the reading position).
        var position: @MainActor (_ post: Int, _ token: Int) -> Void = { _, _ in }
        /// The user tapped the menu button or the author of message `post` in document `token`; `anchor` is the button's
        /// rectangle in the web view's own coordinates (nil when the page gave none).
        var menu: @MainActor (_ post: Int, _ source: MessageMenuSource, _ anchor: CGRect?, _ token: Int) -> Void = { _, _, _, _ in }
        /// The user chose "Citer extrait" or "Citer gras" over `text`, selected in message `post` of document `token` (LOT-086).
        var quote: @MainActor (_ post: Int, _ text: String, _ bold: Bool, _ token: Int) -> Void = { _, _, _, _ in }
        /// The user tapped a posted picture; `images` are those the viewer may show (policy C applied here), opened on `index`.
        var image: @MainActor (_ images: [GalleryImage], _ index: Int, _ token: Int) -> Void = { _, _, _ in }
        /// A short sentence for the reader's feedback line (the result of "Enregistrer dans Photos", #615).
        var notice: @MainActor (_ text: String) -> Void = { _ in }
        /// The reader left the screen, or came back to it without an `onAppear` (`ReaderWebController+Presence`, issue #750).
        var left: @MainActor () -> Void = {}, returned: @MainActor () -> Void = {}
    }

    /// The content world of `reader.js` and of its message channel; the page's own world cannot see either.
    static let world = WKContentWorld.world(name: "SwiftHFRReader")
    /// Name of the message channel (`window.webkit.messageHandlers.reader` in the reader's world).
    static let channel = "reader"
    /// Most images routed per document, so a hostile page cannot make the app hold an unbounded list.
    static let maximumImages = 5_000
    /// Image downloads in flight at once; the others wait their turn.
    static let maximumConcurrentImages = 6

    let webView: QuoteMenuWebView
    var events = Events()
    var ignoresPageTaps = false // a composer is open over the page (#653): it scrolls, its taps (`isTapAction`) do nothing
    /// What the link menu does outside the web view (`ReaderWebController+LinkMenu`); tests replace it.
    var linkMenuEnvironment = ReaderLinkMenu.Environment.live
    /// The in-app text size: applied to the shown document at once (no reload) and to every next one from its start (LOT-169).
    var textScale = TextScale.standard {
        didSet {
            guard textScale != oldValue else { return }
            installUserScripts()
            applyTextScale()
        }
    }

    /// The theme colours (LOT-121): applied like `textScale`, live and from each next document's start.
    var theme = ThemeAppearance.standard {
        didSet {
            guard theme != oldValue else { return }
            applyUnderPageBackground()
            installUserScripts()
            applyTheme()
        }
    }

    /// What the bars and banners cover of the web view, which runs under them (LOT-186; `ReaderWebController+Scroll`).
    var obscuredInsets = UIEdgeInsets.zero {
        didSet { if obscuredInsets != oldValue { applyObscuredInsets(from: oldValue) } }
    }

    let imageFetcher: ReaderImageFetcher
    let autoLoadsThirdPartyImages: @Sendable () -> Bool
    /// The document shown, or loading; nil before the first and after a load stopped before it was ready.
    private(set) var document: ReaderDocument?
    /// The token of the shown document once it reported ready; until then `stopLoading()` forgets the document (issue #566).
    private var readyToken: Int?
    /// The main-frame navigation of the shown document while it may still report ready; nil once stopped or failed.
    private var pageNavigation: WKNavigation?
    /// The shown document's navigation failed once and was started again; a second failure is reported (issue #566).
    private var reloadedAfterFailure = false
    /// `stopLoading()` ran and the screen has not come back (`resume()`): `show` loads nothing, so a re-render of the hidden
    /// view cannot restart the load just stopped (issue #566).
    var stopped = false
    /// The document `stopLoading()` cut, and whether SwiftUI's last word was `onDisappear` (`ReaderWebController+Presence`).
    var stoppedDocument: ReaderDocument?, disappeared = false
    /// The reading top (`ReaderScrollGeometry`) a refresh restores; the insets may change before the next document is ready.
    private var savedReadingTop: CGFloat?
    private var appliedScrollID: Int?
    private var running: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var waiting: [(key: ObjectIdentifier, start: () -> Void)] = []
    /// Third-party image URLs the user tapped in the current document, as `reader.js` reported them. Consent lives here,
    /// never in the image URL: the page's own markup can name the `hfrreader:` scheme (an `img` or a CSS `url()`), and
    /// WebKit's preload scanner requests it before `reader.js` runs.
    private(set) var consented: Set<String> = []
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
        let proxy = ReaderSchemeProxy()
        configuration.setURLSchemeHandler(proxy, forURLScheme: TopicHTMLBuilder.scheme)
        let messages = ReaderMessageProxy()
        configuration.userContentController.addScriptMessageHandler(messages, contentWorld: Self.world, name: Self.channel)
        webView = QuoteMenuWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.onQuoteSelection = { [weak self] bold in self?.requestSelectionQuote(bold: bold) }
        webView.onWindowChange = { [weak self] inWindow in self?.windowDidChange(inWindow: inWindow) }
        installUserScripts()
        proxy.owner = self
        messages.owner = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        // True so WebKit consults `contextMenuConfigurationForElement` (our menu, no preview); with it off it shows its own sheet.
        webView.allowsLinkPreview = true
        webView.isInspectable = false
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        trackUnderPageBackground()
        // Insets come from the SwiftUI layout (`obscuredInsets`): UIKit's safe area does not see the reader's banners.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
    }

    /// Shows `document` unless it is already the one shown. Nothing happens for nil (the screen shows its own state). A document
    /// whose load `stopLoading()` cut before it was ready is no longer the one shown, so showing it again loads it (issue #566).
    func show(_ document: ReaderDocument?) {
        guard let document else { return }
        guard !stopped else {
            ReaderLog.debug("show skipped token=\(document.token): stopped")
            return
        }
        guard document.token != self.document?.token else {
            ReaderLog.debug("show skipped token=\(document.token) ready=\(readyToken == document.token)")
            return
        }
        ReaderLog.debug("show loads token=\(document.token)")
        savedReadingTop = document.keepsScrollPosition ? readingTop : nil
        self.document = document
        readyToken = nil
        reloadedAfterFailure = false
        imageRequests.removeAll()
        consented.removeAll()
        loadPage(document)
    }

    /// Starts the main-frame navigation of `document`, remembered to tell its failures from those of another navigation.
    func loadPage(_ document: ReaderDocument) {
        pageNavigation = webView.load(URLRequest(url: Self.pageURL(token: document.token)))
    }

    /// Scrolls to a message of the shown document, once per request.
    func apply(_ request: ScrollRequest?) {
        guard let request, request.id != appliedScrollID, request.token == document?.token else { return }
        appliedScrollID = request.id
        scroll(to: request.anchor)
    }

    /// Stops the page and every image download in flight (the screen goes away). A document that was not ready yet is
    /// forgotten, so the next `show` of it loads it again (issue #566).
    func stopLoading() {
        let wasReady = document != nil && readyToken == document?.token
        ReaderLog.debug("stopLoading token=\(document?.token ?? -1) ready=\(wasReady)")
        webView.stopLoading()
        stopped = true
        stoppedDocument = document
        pageNavigation = nil
        if !wasReady {
            document = nil
            readyToken = nil
        }
        for task in running.values { task.cancel() }
        running.removeAll()
        waiting.removeAll()
    }

    static func pageURL(token: Int) -> URL {
        URL(string: "\(TopicHTMLBuilder.scheme)://page/\(token)") ?? URL(fileURLWithPath: "/")
    }

    private static let stylesheet: Data? = {
        guard let url = Bundle.main.url(forResource: "reader", withExtension: "css") else { return nil }
        return try? Data(contentsOf: url)
    }()

    // MARK: - Messages from reader.js

    func receive(_ message: WKScriptMessage) -> Any? {
        guard message.frameInfo.isMainFrame, let decoded = try? ReaderBridgeMessage.decode(message.body) else { return nil }
        guard let document, decoded.token == document.token else {
            if case .ready = decoded.message {
                ReaderLog.debug("ready dropped token=\(decoded.token) shown=\(self.document?.token ?? -1)")
            }
            return nil
        }
        return handle(decoded.message, in: document)
    }

    /// Acts on a decoded message of the shown document. `receive` is the entry point of the page (main frame and token checked
    /// first); this one is internal only so tests can drive the actions without a web view round trip.
    func handle(_ message: ReaderBridgeMessage, in document: ReaderDocument) -> Any? {
        if ignoresPageTaps, message.isTapAction { return nil }
        switch message {
        case .images(let urls):
            return decisions(for: urls)
        case .tap(let url):
            return ignoresPageTaps ? false : recordTap(url)
        case .ready:
            documentIsReady(document, token: document.token)
            return nil
        case .position(let post):
            events.position(post, document.token)
            return nil
        case .quote(let post, let text, let bold):
            events.quote(post, text, bold, document.token)
            return nil
        case .video(let post, let index):
            events.video(post, index, document.token)
            return nil
        case .menu(let post, let source, let anchor):
            // `getBoundingClientRect` counts from the bars' edge (`obscuredContentInsets`): the view starts above it.
            let anchor = anchor?.offsetBy(dx: 0, dy: obscuredInsets.top)
            events.menu(post, source, anchor, document.token)
            return nil
        case .image(let urls, let index):
            return openViewer(urls: urls, index: index, token: document.token)
        }
    }

    /// The user tapped a placeholder: consent for that exact URL, third-party only, in this document only.
    private func recordTap(_ text: String?) -> Bool {
        guard let text, let url = URL(string: text), ImagePolicy.classify(url) == .thirdParty,
              consented.count < Self.maximumImages else { return false }
        consented.insert(text)
        return true
    }

    private func documentIsReady(_ document: ReaderDocument, token: Int) {
        // A size or a colour changed while this document was loading reached the previous one: set them again.
        applyTextScale()
        applyTheme()
        if let anchor = document.anchor {
            scroll(to: anchor, landing: true)
        } else if let readingTop = savedReadingTop {
            scroll(toReadingTop: readingTop)
        }
        savedReadingTop = nil
        readyToken = token
        ReaderLog.debug("ready accepted token=\(token)")
        events.ready(token)
    }

    /// The shown document's navigation failed before it was ready: it is loaded once more, then the failure is reported, so
    /// the screen never waits for a page that will not come (issue #566). Another navigation's failure (a link the policy
    /// refused, a document replaced or stopped since) changes nothing.
    func pageNavigationFailed(_ navigation: WKNavigation?, error: any Error) {
        let code = (error as NSError).code
        guard let document, let navigation, navigation === pageNavigation, readyToken != document.token else {
            ReaderLog.debug("navigation failure ignored code=\(code)")
            return
        }
        retryOrReport(document, reason: "navigation failed code=\(code)")
    }

    /// The content process died (memory pressure on a huge page). A document already shown is loaded again; one not ready
    /// yet follows the reload-once rule, so a page that kills the process every time ends on the retry, not a spinner.
    func contentProcessTerminated() {
        guard let document else { return }
        guard readyToken != document.token else {
            ReaderLog.debug("content process terminated token=\(document.token) ready=true: reloading")
            // The web view is blank again: the reload is a new load, under the same once rule, or its failure goes unseen.
            readyToken = nil
            reloadedAfterFailure = false
            loadPage(document)
            return
        }
        retryOrReport(document, reason: "content process terminated")
    }

    /// Loads the not-ready `document` once more, or reports it after a second failure (issue #566).
    private func retryOrReport(_ document: ReaderDocument, reason: String) {
        pageNavigation = nil
        guard reloadedAfterFailure else {
            ReaderLog.debug("\(reason) token=\(document.token): reloading")
            reloadedAfterFailure = true
            loadPage(document)
            return
        }
        ReaderLog.debug("\(reason) again token=\(document.token): reported")
        events.failed(document.token)
    }
}

// MARK: - hfrreader: scheme

extension ReaderWebController {
    func start(_ task: any WKURLSchemeTask) {
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

    func stop(_ task: any WKURLSchemeTask) {
        let key = ObjectIdentifier(task)
        running[key]?.cancel()
        running[key] = nil
        waiting.removeAll { $0.key == key }
        startWaitingImages()
    }

    private func startImage(_ task: any WKURLSchemeTask, url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let source = items.first(where: { $0.name == "u" })?.value, let imageURL = URL(string: source) else {
            return fail(task)
        }
        // The decision is taken again here: the page's own markup could name this scheme, and only a tap the app
        // recorded consents to a third party, never to a blocked host.
        let origin = ImagePolicy.classify(imageURL)
        let autoLoads = autoLoadsThirdPartyImages()
        let decision = ImageDecision(origin: origin, autoLoadsThirdParty: autoLoads, tapped: consented.contains(source))
        if imageRequests.count < Self.maximumImages { imageRequests.append((imageURL, decision == .load)) }
        guard decision == .load else { return fail(task) }
        let key = ObjectIdentifier(task)
        let fetcher = imageFetcher
        // A redirect may reach a third party when this image was one, or when the setting loads third parties anyway.
        let allowsThirdParty = origin == .thirdParty || autoLoads
        let start = { [weak self] in
            guard let self else { return }
            self.running[key] = Task { [weak self] in
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
                self.startWaitingImages()
            }
        }
        waiting.append((key, start))
        startWaitingImages()
    }

    /// Starts waiting downloads while fewer than `maximumConcurrentImages` run.
    private func startWaitingImages() {
        while running.count < Self.maximumConcurrentImages, !waiting.isEmpty {
            waiting.removeFirst().start()
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
