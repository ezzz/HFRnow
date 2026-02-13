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
    var actionHandler: any MessageWebActionHandling
    var onWebAction: ((MessageWebAction) -> Void)?

    init(
        fileURL: URL? = nil,
        readAccessURL: URL? = nil,
        anchor: String? = nil,
        initialScroll: InitialScroll? = nil,
        currentPage: Int = 1,
        maxPage: Int = 1,
        actionHandler: any MessageWebActionHandling = MessageWebActionHandler(),
        onWebAction: ((MessageWebAction) -> Void)? = nil
    ) {
        self.fileURL = fileURL
        self.readAccessURL = readAccessURL
        self.anchor = anchor
        self.initialScroll = initialScroll
        self.currentPage = currentPage
        self.maxPage = maxPage
        self.actionHandler = actionHandler
        self.onWebAction = onWebAction
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .systemGray6
        webView.scrollView.backgroundColor = .systemGray6
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
        print("WebView.updateUIView anchor:", anchor as Any, "fileURL:", fileURL as Any, "baseURL:", readAccessURL as Any)

        if let fileURL = fileURL, let readAccessURL = readAccessURL {
            webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessURL)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        var anchor: String?
        var initialScroll: WebView.InitialScroll?

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("WKWebView didFinish. anchor =", anchor as Any, "initialScroll =", String(describing: initialScroll), "url:", webView.url?.absoluteString ?? "nil")

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
                Color(.systemGray6)

                WebView(
                    fileURL: fileURL,
                    readAccessURL: cacheURL,
                    anchor: anchor,
                    initialScroll: initialScroll,
                    currentPage: page,
                    maxPage: maxPage,
                    onWebAction: handleWebAction
                )
                    .id(page) // force a new WKWebView per page
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
                    AnswerView(topicURL: topicAnswerURL, composerDraftText: $composerDraftText, isComposerPresented: $isComposerPresented, isComposerFocused: $isComposerFocused)
                        .presentationDetents([.large])
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

                            Spacer()
                            Button {
                                isComposerPresented = true
                            } label: {
                                Label("New", systemImage: "plus")
                            }
                            //.buttonStyle(.glassProminent)
                        }
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
