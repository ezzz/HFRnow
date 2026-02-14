//
//  MessagesView.swift
//  SuperHFRplus
//
//  Created by Bruno ARENE on 9/3/25.
//

import SwiftUI
import WebKit
import UIKit
import SafariServices

struct WebView: UIViewRepresentable {
    enum InitialScroll {
        case top
        case bottom
    }

    let fileURL: URL?
    let readAccessURL: URL?
    var anchor: String?
    var initialScroll: InitialScroll?
    var currentPage: Int
    var maxPage: Int
    var colorScheme: ColorScheme
    var actionHandler: any MessageWebActionHandling
    var onWebAction: ((MessageWebAction) -> Void)?
    var onContentReady: (() -> Void)?
    var onScrollPositionChange: ((Bool) -> Void)?

    init(
        fileURL: URL? = nil,
        readAccessURL: URL? = nil,
        anchor: String? = nil,
        initialScroll: InitialScroll? = nil,
        currentPage: Int = 1,
        maxPage: Int = 1,
        colorScheme: ColorScheme = .light,
        actionHandler: any MessageWebActionHandling = MessageWebActionHandler(),
        onWebAction: ((MessageWebAction) -> Void)? = nil,
        onContentReady: (() -> Void)? = nil,
        onScrollPositionChange: ((Bool) -> Void)? = nil
    ) {
        self.fileURL = fileURL
        self.readAccessURL = readAccessURL
        self.anchor = anchor
        self.initialScroll = initialScroll
        self.currentPage = currentPage
        self.maxPage = maxPage
        self.colorScheme = colorScheme
        self.actionHandler = actionHandler
        self.onWebAction = onWebAction
        self.onContentReady = onContentReady
        self.onScrollPositionChange = onScrollPositionChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let bootstrapThemeScriptSource: String
        if colorScheme == .dark {
            bootstrapThemeScriptSource = """
            (function() {
              var root = document.documentElement;
              if (!root) { return; }
              root.setAttribute('data-theme', 'dark');
              root.style.setProperty('--color-message-background', '#242529');
              root.style.setProperty('--color-message-modo-background', '#4A2E3C');
              root.style.setProperty('--color-separator-new-message', 'rgba(206, 206, 206, 0.30)');
              root.style.setProperty('--color-text', '#CECECE');
              root.style.setProperty('--color-text2', '#3C3C3C');
              root.style.setProperty('--color-background-bars', 'rgba(46, 47, 51, 0.70)');
              root.style.setProperty('--color-searchintra-nextresults', 'rgba(46, 47, 51, 0.90)');
              root.style.setProperty('--color-border-quotation', 'rgba(255, 255, 255, 0.20)');
              root.style.setProperty('--color-border-avatar', '#222222');
              root.style.setProperty('--color-text-pseudo', '#CECECE');
              root.style.setProperty('--color-text-pseudo-bl', 'rgba(206, 206, 206, 0.50)');
              root.style.setProperty('--imagefile-avatar', 'url(avatar_male_gray_on_dark_48x48.png)');
              root.style.setProperty('--imagefile-loadinfo', 'url(loadinfo.net.gif)');
            })();
            """
        } else {
            bootstrapThemeScriptSource = """
            (function() {
              var root = document.documentElement;
              if (!root) { return; }
              root.setAttribute('data-theme', 'light');
            })();
            """
        }

        let contentController = WKUserContentController()
        let bootstrapThemeScript = WKUserScript(
            source: bootstrapThemeScriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(bootstrapThemeScript)
        contentController.add(context.coordinator, name: "scrollState")

        let scrollTrackingScript = WKUserScript(
            source: """
            (function() {
              function notifyScrollState() {
                var root = document.documentElement || {};
                var body = document.body || {};
                var viewport = window.innerHeight || root.clientHeight || 0;
                var scrollY = window.scrollY || window.pageYOffset || root.scrollTop || body.scrollTop || 0;
                var contentHeight = Math.max(
                  body.scrollHeight || 0,
                  root.scrollHeight || 0,
                  body.offsetHeight || 0,
                  root.offsetHeight || 0
                );
                var distanceToBottom = contentHeight - (scrollY + viewport);
                var atBottom = distanceToBottom <= 2;
                try { window.webkit.messageHandlers.scrollState.postMessage(atBottom); } catch (e) {}
              }

              window.addEventListener('scroll', notifyScrollState, { passive: true });
              window.addEventListener('resize', notifyScrollState, { passive: true });
              window.addEventListener('load', function() {
                setTimeout(notifyScrollState, 0);
                setTimeout(notifyScrollState, 120);
              });
              setTimeout(notifyScrollState, 0);
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(scrollTrackingScript)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        let baseBackgroundColor: UIColor = colorScheme == .dark ? .black : .systemGray6
        webView.backgroundColor = baseBackgroundColor
        webView.scrollView.backgroundColor = baseBackgroundColor
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = baseBackgroundColor
        }
        webView.navigationDelegate = context.coordinator
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.anchor = anchor
        context.coordinator.initialScroll = initialScroll
        context.coordinator.colorScheme = colorScheme
        let baseBackgroundColor: UIColor = colorScheme == .dark ? .black : .systemGray6
        webView.backgroundColor = baseBackgroundColor
        webView.scrollView.backgroundColor = baseBackgroundColor
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = baseBackgroundColor
        }
        print("WebView.updateUIView anchor:", anchor as Any, "fileURL:", fileURL as Any, "baseURL:", readAccessURL as Any)

        if let fileURL = fileURL, let readAccessURL = readAccessURL {
            let shouldReload =
                context.coordinator.loadedFileURL != fileURL ||
                context.coordinator.loadedReadAccessURL != readAccessURL

            if shouldReload {
                context.coordinator.loadedFileURL = fileURL
                context.coordinator.loadedReadAccessURL = readAccessURL
                context.coordinator.lastAppliedTheme = nil
                context.coordinator.isWaitingForThemeApplication = true
                context.coordinator.didNotifyContentReadyForCurrentLoad = false
                webView.isHidden = true
                webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessURL)
            } else {
                context.coordinator.applyThemeIfNeeded(in: webView)
                if !context.coordinator.isWaitingForThemeApplication {
                    webView.isHidden = false
                }
            }
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebView
        var anchor: String?
        var initialScroll: WebView.InitialScroll?
        var colorScheme: ColorScheme
        var loadedFileURL: URL?
        var loadedReadAccessURL: URL?
        var lastAppliedTheme: String?
        var isWaitingForThemeApplication = false
        var didNotifyContentReadyForCurrentLoad = false

        init(_ parent: WebView) {
            self.parent = parent
            self.colorScheme = parent.colorScheme
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("WKWebView didFinish. anchor =", anchor as Any, "initialScroll =", String(describing: initialScroll), "url:", webView.url?.absoluteString ?? "nil")
            applyThemeIfNeeded(in: webView, force: true) {
                self.isWaitingForThemeApplication = false
                webView.isHidden = false
                self.notifyContentReadyIfNeeded()
            }

            if let a = anchor, !a.isEmpty {
                // Probe: check if element exists by id or name
                let probe = """
                (function(a){
                  var byId = document.getElementById(a);
                  var byName = document.getElementsByName(a)[0];
                  return 'probe byId='+(!!byId)+' byName='+(!!byName)+' a='+a;
                })('\(a)')
                """
                webView.evaluateJavaScript(probe) { result, error in
                    print("Anchor probe:", result ?? "nil", "error:", error?.localizedDescription ?? "none")
                }

                // Timed scroll with fallback to location.hash
                let js = """
                setTimeout(function(){
                  var a = '\(a)';
                  var el = document.getElementById(a) || document.getElementsByName(a)[0];
                  if (el) {
                    try { el.scrollIntoView({behavior:'auto', block:'start', inline:'nearest'}); }
                    catch(e) { el.scrollIntoView(true); }
                  } else {
                    try { location.hash = '#' + a; } catch(e) {}
                  }
                }, 50);
                """

                webView.evaluateJavaScript(js) { _, error in
                    if let error = error {
                        print("Anchor scroll JS error:", error.localizedDescription)
                    } else {
                        print("Anchor scroll JS executed")
                    }
                }
                return
            }

            // No anchor: apply initial scroll if requested
            guard let initial = initialScroll else { return }
            let js: String
            switch initial {
            case .top:
                js = "setTimeout(function(){ try { window.scrollTo(0, 0); } catch(e) {} }, 50);"
            case .bottom:
                js = "setTimeout(function(){ try { window.scrollTo(0, Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)); } catch(e) {} }, 50);"
            }
            webView.evaluateJavaScript(js) { _, error in
                if let error = error {
                    print("Initial scroll JS error:", error.localizedDescription)
                } else {
                    print("Initial scroll JS executed (\(initial))")
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "scrollState" else { return }

            let isAtBottom: Bool
            if let boolValue = message.body as? Bool {
                isAtBottom = boolValue
            } else if let numberValue = message.body as? NSNumber {
                isAtBottom = numberValue.boolValue
            } else {
                return
            }

            DispatchQueue.main.async {
                self.parent.onScrollPositionChange?(isAtBottom)
            }
        }

        private func notifyContentReadyIfNeeded() {
            guard !didNotifyContentReadyForCurrentLoad else { return }
            didNotifyContentReadyForCurrentLoad = true
            parent.onContentReady?()
        }

        func applyThemeIfNeeded(
            in webView: WKWebView,
            force: Bool = false,
            completion: (() -> Void)? = nil
        ) {
            let targetTheme = colorScheme == .dark ? "dark" : "light"
            guard force || lastAppliedTheme != targetTheme else {
                completion?()
                return
            }

            let script = """
            (function() {
              var theme = '\(targetTheme)';
              var root = document.documentElement;
              if (!root) { return; }
              root.setAttribute('data-theme', theme);

              var meta = document.querySelector("meta[name='color-scheme']");
              if (!meta && document.head) {
                meta = document.createElement('meta');
                meta.setAttribute('name', 'color-scheme');
                document.head.appendChild(meta);
              }
              if (meta) {
                meta.setAttribute('content', 'light dark');
              }

              var cssLink = document.getElementById('light-styles');
              if (cssLink) {
                cssLink.setAttribute('href', 'style-liste-light.css');
              }

              var darkOverrides = {
                '--color-message-background': '#242529',
                '--color-message-modo-background': '#4A2E3C',
                '--color-separator-new-message': 'rgba(206, 206, 206, 0.30)',
                '--color-text': '#CECECE',
                '--color-text2': '#3C3C3C',
                '--color-background-bars': 'rgba(46, 47, 51, 0.70)',
                '--color-searchintra-nextresults': 'rgba(46, 47, 51, 0.90)',
                '--color-border-quotation': 'rgba(255, 255, 255, 0.20)',
                '--color-border-avatar': '#222222',
                '--color-text-pseudo': '#CECECE',
                '--color-text-pseudo-bl': 'rgba(206, 206, 206, 0.50)',
                '--imagefile-avatar': 'url(avatar_male_gray_on_dark_48x48.png)',
                '--imagefile-loadinfo': 'url(loadinfo.net.gif)'
              };

              var overrideKeys = Object.keys(darkOverrides);
              var storageKey = '__hfrswiftThemeBaseVars';
              var baseVars = window[storageKey];
              if (!baseVars) {
                baseVars = {};
                overrideKeys.forEach(function(key) {
                  baseVars[key] = root.style.getPropertyValue(key);
                });
                window[storageKey] = baseVars;
              }

              if (theme === 'dark') {
                overrideKeys.forEach(function(key) {
                  root.style.setProperty(key, darkOverrides[key]);
                });
              } else {
                overrideKeys.forEach(function(key) {
                  var baseValue = baseVars[key];
                  if (baseValue && baseValue.trim().length > 0) {
                    root.style.setProperty(key, baseValue);
                  } else {
                    root.style.removeProperty(key);
                  }
                });
              }
            })();
            """

            webView.evaluateJavaScript(script) { [weak self] _, error in
                if let error = error {
                    print("Theme JS error:", error.localizedDescription)
                } else {
                    self?.lastAppliedTheme = targetTheme
                    print("Theme JS applied:", targetTheme)
                }
                completion?()
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let navigationType = MessageWebNavigationType(navigationAction.navigationType)
            let action = parent.actionHandler.action(
                for: url,
                navigationType: navigationType,
                currentPage: parent.currentPage,
                maxPage: parent.maxPage
            )

            switch action {
            case .allowNavigation:
                decisionHandler(.allow)
            case .ignore:
                decisionHandler(.cancel)
            case .loadPage, .refreshCurrentPage, .openInternalTopic, .openExternalURL:
                parent.onWebAction?(action)
                decisionHandler(.cancel)
            }
        }
    }
}

private struct SafariInAppView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private extension MessageWebNavigationType {
    init(_ navigationType: WKNavigationType) {
        switch navigationType {
        case .linkActivated:
            self = .linkActivated
        case .formSubmitted:
            self = .formSubmitted
        case .backForward:
            self = .backForward
        case .reload:
            self = .reload
        case .formResubmitted:
            self = .formResubmitted
        case .other:
            self = .other
        @unknown default:
            self = .unknown
        }
    }
}

struct MessagesView: View {
    private struct SafariDestination: Identifiable {
        let id = UUID()
        let url: URL
    }

    let topic: Topic
    let curPage: Int // Stored again as it can be updated when reloading the topic
    let maxPage: Int
    let separatorNewMessages: Bool
    let topicPageLoader: TopicPageLoading
    let topicPageRenderer: TopicPageRendering
    @Environment(\.colorScheme) private var colorScheme

    @State private var page: Int
    @State private var fileURL: URL?
    @State private var cacheURL: URL?
    @State private var errorMessage: String?
    @State private var anchor: String?
    @State private var initialScroll: WebView.InitialScroll?
    @State private var topicAnswerURL: URL?
    @AppStorage("composerDraftText") private var composerDraftText: String = ""
    @State private var isComposerPresented = false
    @State private var isPresentingComposer = false  // This will be removed now
    @State private var replyText: String = ""
    @State private var isSendingReply = false
    @State private var isComposerMinimized = false
    @State private var animateLoadingSpinner = false
    @FocusState private var isComposerFocused: Bool
    @State private var isPagePickerPresented = false
    @State private var pagePickerInput: String = ""
    @State private var linkedTopic: Topic?
    @State private var navigateToLinkedTopic = false
    @State private var safariDestination: SafariDestination?
    @State private var showWebViewLoadCover = true
    @State private var isWebContentAtBottom = false
    @State private var pendingPostedReply: ReplyPostingResult?
    @State private var showPostSuccessToast = false
    @State private var postSuccessToastText = "Hooray"
    // Remove the unused
    // @State private var isPresentingAddMessage = false

    init(
        topic: Topic,
        curPage: Int,
        maxPage: Int,
        separatorNewMessages: Bool,
        topicPageLoader: TopicPageLoading = ObjCTopicPageLoader(),
        topicPageRenderer: TopicPageRendering = OfflineStorageTopicPageRenderer()
    ) {
        self.topic = topic
        self.curPage = curPage
        self.maxPage = maxPage
        self.separatorNewMessages = separatorNewMessages
        self.topicPageLoader = topicPageLoader
        self.topicPageRenderer = topicPageRenderer
        self._page = State(initialValue: curPage)

        // extraire l’ancre (#xxxx) si présente
        if let url = URL(string: topic.aURL), let fragment = url.fragment {
            self._anchor = State(initialValue: fragment)
            print("INIT extracted anchor:", fragment)
        }
    }

    private func urlForPage(_ page: Int) -> String {
        print("Current url: \(self.topic.aURL ?? "empty")")
        if let currentURL = topic.aURL, currentURL.contains("page=") {
            let legacyURL = topic.getURLforPage(Int32(page))
            if let legacyURL, !legacyURL.isEmpty {
                return legacyURL
            }
        }

        guard var comps = URLComponents(string: self.topic.aURL) else { return "" }
        var queryItems = comps.queryItems ?? []
        if let index = queryItems.firstIndex(where: { $0.name == "page" }) {
            queryItems[index].value = "\(page)"
        } else {
            queryItems.append(URLQueryItem(name: "page", value: "\(page)"))
        }
        comps.queryItems = queryItems
        // ⚠️ On ne garde pas le fragment quand on change de page
        comps.fragment = nil
        return comps.string ?? ""
    }

    private func loadPage(_ page: Int) {
        let url = urlForPage(page)
        print("loadPage(\(page)) url:", url, "current anchor:", self.anchor as Any)
        showWebViewLoadCover = true
        isWebContentAtBottom = false
        errorMessage = nil
        topicPageLoader.fetchTopicPage(url: url, anchor: self.anchor) { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                case .success(let content):
                    do {
                        let rendered = try topicPageRenderer.render(html: content.html)
                        self.fileURL = rendered.fileURL
                        self.cacheURL = rendered.readAccessURL
                        if self.fileURL == nil || self.cacheURL == nil {
                            self.errorMessage = "Failed to render topic page to local file."
                        }
                    } catch {
                        self.fileURL = nil
                        self.cacheURL = nil
                        self.errorMessage = error.localizedDescription
                    }
                    self.page = page
                    self.topicAnswerURL = content.topicAnswerURL
                }
            }
        }
    }

    private func loadDirectURL(_ topicURL: String, initialScroll: WebView.InitialScroll? = nil) {
        guard !topicURL.isEmpty else { return }
        self.anchor = URL(string: topicURL)?.fragment
        self.initialScroll = initialScroll
        showWebViewLoadCover = true
        isWebContentAtBottom = false
        self.errorMessage = nil

        topicPageLoader.fetchTopicPage(url: topicURL, anchor: self.anchor) { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                case .success(let content):
                    do {
                        let rendered = try topicPageRenderer.render(html: content.html)
                        self.fileURL = rendered.fileURL
                        self.cacheURL = rendered.readAccessURL
                    } catch {
                        self.fileURL = nil
                        self.cacheURL = nil
                        self.errorMessage = error.localizedDescription
                    }
                    self.topicAnswerURL = content.topicAnswerURL
                }
            }
        }
    }

    private func normalizedForumTopicURLString(from url: URL) -> String {
        let scheme = (url.scheme ?? "").lowercased()
        let host = (url.host ?? "").lowercased()

        guard (scheme == "http" || scheme == "https"), host == "forum.hardware.fr" else {
            return url.absoluteString
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var relativeURL = url.path
        if let query = components?.percentEncodedQuery, !query.isEmpty {
            relativeURL += "?\(query)"
        }
        if let fragment = components?.percentEncodedFragment, !fragment.isEmpty {
            relativeURL += "#\(fragment)"
        }

        return relativeURL.isEmpty ? "/" : relativeURL
    }

    private func openInternalTopic(_ url: URL) {
        let topicURLString = normalizedForumTopicURLString(from: url)
        guard !topicURLString.isEmpty else { return }

        let pageFromURL = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "page" })?
            .value
            .flatMap(Int.init) ?? 1
        let boundedPage = max(pageFromURL, 1)
        let derivedMaxPage = max(maxPage, boundedPage)

        let topicForNavigation = Topic()
        topicForNavigation._aTitle = topic._aTitle
        topicForNavigation.aURL = topicURLString
        topicForNavigation.aURLOfLastPage = topicURLString
        topicForNavigation.curTopicPage = Int32(boundedPage)
        topicForNavigation.maxTopicPage = Int32(derivedMaxPage)

        linkedTopic = topicForNavigation
        navigateToLinkedTopic = true
    }

    private func webViewInitialScroll(_ value: MessageWebInitialScroll) -> WebView.InitialScroll {
        switch value {
        case .top:
            return .top
        case .bottom:
            return .bottom
        }
    }

    private func handleWebAction(_ action: MessageWebAction) {
        switch action {
        case .allowNavigation:
            break
        case .ignore:
            break
        case .loadPage(let targetPage, let initialScroll):
            navigateToPage(targetPage, initialScroll: webViewInitialScroll(initialScroll))
        case .refreshCurrentPage:
            loadPage(page)
        case .openInternalTopic(let url):
            if url.scheme?.lowercased() == "file" {
                loadDirectURL(url.absoluteString)
            } else {
                openInternalTopic(url)
            }
        case .openExternalURL(let url):
            safariDestination = SafariDestination(url: url)
        }
    }

    @ViewBuilder
    private var linkedTopicNavigationLink: some View {
        NavigationLink(
            "",
            isActive: $navigateToLinkedTopic
        ) {
            if let linkedTopic {
                MessagesView(
                    topic: linkedTopic,
                    curPage: Int(linkedTopic.curTopicPage),
                    maxPage: max(Int(linkedTopic.maxTopicPage), 1),
                    separatorNewMessages: true
                )
                .toolbar(.hidden, for: .tabBar)
            } else {
                EmptyView()
            }
        }
        .hidden()
        .allowsHitTesting(false)
    }

    private func uniqueValidPages(_ candidates: [Int], excluding excludedTargets: Set<Int> = []) -> [Int] {
        var seen = excludedTargets
        return candidates.compactMap { target in
            guard (1...maxPage).contains(target), target != page else { return nil }
            guard seen.insert(target).inserted else { return nil }
            return target
        }
    }

    private var backwardFirstPages: [Int] {
        uniqueValidPages([1, 2, 3])
    }

    private var backwardLastPages: [Int] {
        uniqueValidPages([page - 3, page - 2, page - 1], excluding: Set(backwardFirstPages))
    }

    private var forwardFirstPages: [Int] {
        uniqueValidPages([page + 1, page + 2, page + 3])
    }

    private var forwardLastPages: [Int] {
        uniqueValidPages([maxPage - 2, maxPage - 1, maxPage], excluding: Set(forwardFirstPages))
    }

    private func pageMenuLabel(_ target: Int) -> String {
        "Page \(target)"
    }

    private func openPagePicker() {
        pagePickerInput = "\(page)"
        isPagePickerPresented = true
    }

    private func navigateToPage(_ target: Int, initialScroll: WebView.InitialScroll) {
        guard (1...maxPage).contains(target), target != page else { return }
        anchor = nil
        self.initialScroll = initialScroll
        loadPage(target)
    }

    private func submitPagePicker() {
        let trimmed = pagePickerInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let target = Int(trimmed), (1...maxPage).contains(target) else { return }
        navigateToPage(target, initialScroll: .top)
    }

    private var shouldShowBottomRefreshButton: Bool {
        page >= maxPage && isWebContentAtBottom
    }

    private func refreshCurrentPageAtBottom() {
        anchor = nil
        initialScroll = .bottom
        loadPage(page)
    }

    private func handleReplySuccess(_ result: ReplyPostingResult) {
        pendingPostedReply = result
    }

    private func handleComposerDismissalIfNeeded() {
        guard pendingPostedReply != nil else { return }
        pendingPostedReply = nil

        postSuccessToastText = "Hooray"
        withAnimation {
            showPostSuccessToast = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation {
                showPostSuccessToast = false
            }
        }

        guard page >= maxPage else { return }
        anchor = nil
        initialScroll = .bottom
        loadPage(maxPage)
    }

    @ViewBuilder
    private func backwardContextMenuItems() -> some View {
        if page > 1 {
            if page > 2 {
                Button {
                    // Go to first page: start at top
                    self.anchor = nil
                    self.initialScroll = .top
                    loadPage(1)
                } label: {
                    Label("Première page", systemImage: "backward.end.alt")
                }
            }
            Button {
                // Previous page: start at bottom
                self.anchor = nil
                self.initialScroll = .bottom
                loadPage(page - 1)
            } label: {
                Label("Page précédente", systemImage: "backward.end")
            }  
        }
        Divider()
        if maxPage > 1 {
            Button {
                openPagePicker()
            } label: {
                Text("Page numéro...")
            }
        }
    }

    @ViewBuilder
    private func forwardContextMenuItems() -> some View {
        if page < maxPage {
            Button {
                // Next page: start at top
                self.anchor = nil
                self.initialScroll = .top
                loadPage(page + 1)
            } label: {
                Label("Page suivante", systemImage: "forward.end")
            }
            Button {
                // Dernière réponse: start at top
                self.anchor = nil
                self.initialScroll = .bottom
                loadPage(maxPage)
            } label: {
                Label("Dernière réponse", systemImage: "forward.end.alt")
            }
        }
        Divider()
        if maxPage > 1 {
            Button {
                openPagePicker()
            } label: {
                Text("Page numéro...")
            }
        }
    }

    var body: some View {
        // Use ViewBuilder implicit grouping to avoid generic inference issues with Group
        if let errorMessage {
            Text("Erreur : \(errorMessage)").foregroundColor(.red)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 2) {
                            Text(topic._aTitle ?? "Messages")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text("\(page)/\(maxPage)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .multilineTextAlignment(.center)
                    }
                }
                .onAppear {
                    loadPage(page)
                }
                .background(linkedTopicNavigationLink)
                .sheet(item: $safariDestination) { destination in
                    SafariInAppView(url: destination.url)
                        .ignoresSafeArea()
                }
        } else if fileURL != nil && cacheURL != nil {
            ZStack {
                Color(colorScheme == .dark ? .black : .systemGray6)

                WebView(
                    fileURL: fileURL,
                    readAccessURL: cacheURL,
                    anchor: anchor,
                    initialScroll: initialScroll,
                    currentPage: page,
                    maxPage: maxPage,
                    colorScheme: colorScheme,
                    onWebAction: handleWebAction,
                    onContentReady: {
                        withAnimation(.easeOut(duration: 0.14)) {
                            showWebViewLoadCover = false
                        }
                    },
                    onScrollPositionChange: { isAtBottom in
                        if isWebContentAtBottom != isAtBottom {
                            isWebContentAtBottom = isAtBottom
                        }
                    }
                )
                    .id(page) // force a new WKWebView per page

                if showWebViewLoadCover {
                    Color(colorScheme == .dark ? .black : .systemGray6)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .ignoresSafeArea()
            .navigationBarTitleDisplayMode(.inline)

                .simultaneousGesture(
                    DragGesture().onEnded { value in
                        let horizontal = value.translation.width
                        let vertical = value.translation.height
                        let minDistance: CGFloat = 120
                        let maxVerticalRatio: CGFloat = 0.5
                        if abs(horizontal) > minDistance && abs(vertical) < abs(horizontal) * maxVerticalRatio {
                            if horizontal < 0, page < maxPage {
                                // Next page: start at top
                                self.anchor = nil
                                self.initialScroll = .top
                                loadPage(page + 1)
                            } else if horizontal > 0, page > 1 {
                                // Previous page: start at bottom
                                self.anchor = nil
                                self.initialScroll = .bottom
                                loadPage(page - 1)
                            }
                        }
                    }
                )
                .sheet(isPresented: $isComposerPresented) {
                    AnswerView(
                        topicURL: topicAnswerURL,
                        onPostSuccess: handleReplySuccess,
                        composerDraftText: $composerDraftText,
                        isComposerPresented: $isComposerPresented,
                        isComposerFocused: $isComposerFocused
                    )
                        .presentationDetents([.large])
                }
                .onChange(of: isComposerPresented) { _, isPresented in
                    if !isPresented {
                        handleComposerDismissalIfNeeded()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 2) {
                            Text(topic._aTitle ?? "Messages")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text("\(page)/\(maxPage)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .multilineTextAlignment(.center)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        // Menu avec options
                        Menu {
                            Button {
                                isComposerPresented = true
                            } label: {
                                Label("Répondre", systemImage: "pencil")
                            }
                            /*
                            Button {
                                print("log")
                            } label: {
                                Label("Haut de la page", systemImage: "arrowshape.up")
                            }
                            Button {
                                print("log")
                            } label: {
                                Label("Bas de la page", systemImage: "arrowshape.down")
                            }
                            Divider()*/
                            Button {
                                print("log")
                            } label: {
                                Label("Sondage", image: "icone_sondage")
                            }
                            Divider()
                            Button {
                                print("log")
                            } label: {
                                Label("Rechercher", systemImage: "magnifyingglass")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                    }
                    if !isComposerPresented {
                        ToolbarItemGroup(placement: .bottomBar) {
                            Button {
                                navigateToPage(page - 1, initialScroll: .bottom)
                            } label: {
                                Image(systemName: "chevron.backward")
                            }
                            .contextMenu {
                                backwardContextMenuItems()
                            }
                            .disabled(page <= 1)

                            Button {
                                navigateToPage(page + 1, initialScroll: .top)
                            } label: {
                                Image(systemName: "chevron.forward")
                            }
                            .contextMenu {
                                forwardContextMenuItems()
                            }
                            .disabled(page >= maxPage)
                        }

                        ToolbarSpacer(.flexible, placement: .bottomBar)

                        if shouldShowBottomRefreshButton {
                            ToolbarItem(placement: .bottomBar) {
                                Button {
                                    refreshCurrentPageAtBottom()
                                } label: {
                                    Text("Rafraichir")
                                }
                                .buttonStyle(.glassProminent)
                                .transition(.opacity.combined(with: .scale))
                            }
                            ToolbarSpacer(.fixed, placement: .bottomBar)
                        }

                        ToolbarItem(placement: .bottomBar) {
                            Button {
                                isComposerPresented = true
                            } label: {
                                Label("New", systemImage: "plus")
                            }
                        }
                        //.buttonStyle(.glassProminent)
                    }
                }
                .alert("Page numéro...", isPresented: $isPagePickerPresented) {
                    TextField("1...\(maxPage)", text: $pagePickerInput)
                        .keyboardType(.numberPad)
                    Button("Annuler", role: .cancel) {}
                    Button("Aller") {
                        submitPagePicker()
                    }
                } message: {
                    Text("Choisir une page entre 1 et \(maxPage)")
                }
                .background(linkedTopicNavigationLink)
                .sheet(item: $safariDestination) { destination in
                    SafariInAppView(url: destination.url)
                        .ignoresSafeArea()
                }
                .overlay(alignment: .top) {
                    if showPostSuccessToast {
                        PostSuccessToastBanner(text: postSuccessToastText)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.22), value: shouldShowBottomRefreshButton)
        } else {
            ZStack {
                //HatchedBackground()
                //    .ignoresSafeArea()
                VStack(spacing: 8) {
                    SpinnerLoading()
                    Text("Chargement...")
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .navigationTitle("My title")
                .navigationBarTitleDisplayMode(.inline)
                //.padding()
            }
        
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(topic._aTitle ?? "Messages")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("\(page)/\(maxPage)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .multilineTextAlignment(.center)
                }
                ToolbarItem(placement: .primaryAction) {
                    // Menu avec options
                    Menu {
                        Button {
                            isComposerPresented = true
                        } label: {
                            Label("Répondre", systemImage: "pencil")
                        }
                        Button {
                            print("log")
                        } label: {
                            Label("Rechercher", systemImage: "magnifyingglass")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        navigateToPage(page - 1, initialScroll: .bottom)
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .contextMenu {
                        backwardContextMenuItems()
                    } preview: {
                        EmptyView()
                    }
                    .disabled(page <= 1)

                    Button {
                        navigateToPage(page + 1, initialScroll: .top)
                    } label: {
                        Image(systemName: "chevron.forward")
                    }
                    .contextMenu {
                        forwardContextMenuItems()
                    } preview: {
                        EmptyView()
                    }
                    .disabled(page >= maxPage)

                    Spacer()
                    Button {
                        isComposerPresented = true
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .alert("Page numéro...", isPresented: $isPagePickerPresented) {
                TextField("1...\(maxPage)", text: $pagePickerInput)
                    .keyboardType(.numberPad)
                Button("Annuler", role: .cancel) {}
                Button("Aller") {
                    submitPagePicker()
                }
            } message: {
                Text("Choisir une page entre 1 et \(maxPage)")
            }
            .onAppear {
                loadPage(page)
            }
            .background(linkedTopicNavigationLink)
            .sheet(item: $safariDestination) { destination in
                SafariInAppView(url: destination.url)
                    .ignoresSafeArea()
            }
        }
    }
}

struct SpinnerLoading: View {

    var outerColor = Color.gray
    var innerColor = Color.cyan

    @State private var outerAngle: Angle = .degrees(0)
    @State private var innerAngle: Angle = .degrees(0)

    var body: some View {
        ZStack {
            trimmedCircle(color: outerColor, clockwise: true, scale: 1.0)
                .rotationEffect(outerAngle)
            trimmedCircle(color: innerColor, clockwise: false, scale: 0.75)
                .rotationEffect(innerAngle)
        }
        .frame(width: 30, height: 30)
        .onAppear {
            // Animate continuous rotation in place
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                outerAngle = .degrees(360)
            }
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                innerAngle = .degrees(-360)
            }
        }
    }

    private func trimmedCircle(color: Color, clockwise: Bool, scale: CGFloat) -> some View {
        GeometryReader { proxy in
            let borderWidth = min(proxy.size.width, proxy.size.height) / 14
            Circle()
                .trim(from: 0.1, to: 0.9)
                //.inset(by: borderWidth / 2)
                .stroke(color, style: StrokeStyle(lineWidth: borderWidth, lineCap: .round))
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
        }
    }
}

private struct PostSuccessToastBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 6, y: 3)
    }
}

private enum MessagesPreviewFactory {
    final class PreviewTopicPageLoader: TopicPageLoading {
        enum Result {
            case success(TopicPageContent)
            case failure(Error)
        }

        private let result: Result
        private let delay: TimeInterval

        init(result: Result, delay: TimeInterval = 0) {
            self.result = result
            self.delay = delay
        }

        func fetchTopicPage(url: String, anchor: String?, completion: @escaping (Swift.Result<TopicPageContent, Error>) -> Void) {
            let work = {
                switch self.result {
                case .success(let content):
                    completion(.success(content))
                case .failure(let error):
                    completion(.failure(error))
                }
            }

            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            } else {
                work()
            }
        }
    }

    struct PreviewTopicPageRenderer: TopicPageRendering {
        func render(html: String) throws -> TopicPageRenderOutput {
            let baseURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("hfrswift-preview", isDirectory: true)
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

            let fileURL = baseURL
                .appendingPathComponent("topic-\(UUID().uuidString)")
                .appendingPathExtension("htm")
            try html.write(to: fileURL, atomically: false, encoding: .utf8)
            return TopicPageRenderOutput(fileURL: fileURL, readAccessURL: baseURL)
        }
    }

    enum PreviewError: Error, LocalizedError {
        case network

        var errorDescription: String? {
            switch self {
            case .network:
                return "Connexion indisponible"
            }
        }
    }

    static var sampleHTML: String {
        """
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <title>Topic preview</title>
            <style>
              body { font-family: -apple-system; margin: 16px; background: #f7f7f7; color: #111; }
              .post { background: white; border-radius: 10px; padding: 12px; margin-bottom: 10px; }
              .meta { font-size: 12px; color: #6b7280; margin-bottom: 4px; }
            </style>
          </head>
          <body>
            <article class="post">
              <div class="meta">alice - il y a 2 min</div>
              <p>Premiere reponse de preview.</p>
            </article>
            <article class="post">
              <div class="meta">bob - il y a 1 min</div>
              <p>Deuxieme reponse de preview.</p>
            </article>
          </body>
        </html>
        """
    }

    static func sampleTopic(page: Int = 55, maxPage: Int = 120) -> Topic {
        let topic = Topic()
        topic._aTitle = "Topic SwiftUI preview"
        topic.curTopicPage = Int32(page)
        topic.maxTopicPage = Int32(maxPage)
        topic.aURL = "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=42&page=\(page)"
        topic.aURLOfLastPage = "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=42&page=\(maxPage)"
        return topic
    }
}

#Preview("Messages - happy path") {
    NavigationStack {
        MessagesView(
            topic: MessagesPreviewFactory.sampleTopic(),
            curPage: 55,
            maxPage: 120,
            separatorNewMessages: true,
            topicPageLoader: MessagesPreviewFactory.PreviewTopicPageLoader(
                result: .success(
                    TopicPageContent(
                        html: MessagesPreviewFactory.sampleHTML,
                        topicAnswerURL: URL(string: "https://forum.hardware.fr/message.php?config=hfr.inc&cat=13&post=42")
                    )
                )
            ),
            topicPageRenderer: MessagesPreviewFactory.PreviewTopicPageRenderer()
        )
    }
}

#Preview("Messages - loading") {
    NavigationStack {
        MessagesView(
            topic: MessagesPreviewFactory.sampleTopic(page: 12, maxPage: 48),
            curPage: 12,
            maxPage: 48,
            separatorNewMessages: true,
            topicPageLoader: MessagesPreviewFactory.PreviewTopicPageLoader(
                result: .success(
                    TopicPageContent(
                        html: MessagesPreviewFactory.sampleHTML,
                        topicAnswerURL: nil
                    )
                ),
                delay: 3
            ),
            topicPageRenderer: MessagesPreviewFactory.PreviewTopicPageRenderer()
        )
    }
}

#Preview("Messages - error") {
    NavigationStack {
        MessagesView(
            topic: MessagesPreviewFactory.sampleTopic(page: 1, maxPage: 5),
            curPage: 1,
            maxPage: 5,
            separatorNewMessages: true,
            topicPageLoader: MessagesPreviewFactory.PreviewTopicPageLoader(
                result: .failure(MessagesPreviewFactory.PreviewError.network)
            ),
            topicPageRenderer: MessagesPreviewFactory.PreviewTopicPageRenderer()
        )
    }
}
