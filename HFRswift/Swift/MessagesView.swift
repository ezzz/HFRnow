//
//  MessagesView.swift
//  SuperHFRplus
//
//  Created by Bruno ARENE on 9/3/25.
//

import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    enum InitialScroll {
        case top
        case bottom
    }

    let html: String?
    let fileURL: URL?
    let readAccessURL: URL?
    var anchor: String?
    var initialScroll: InitialScroll?

    init(html: String? = nil, fileURL: URL? = nil, readAccessURL: URL? = nil, anchor: String? = nil, initialScroll: InitialScroll? = nil) {
        self.html = html
        self.fileURL = fileURL
        self.readAccessURL = readAccessURL
        self.anchor = anchor
        self.initialScroll = initialScroll
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.anchor = anchor
        context.coordinator.initialScroll = initialScroll
        print("WebView.updateUIView anchor:", anchor as Any, "fileURL:", fileURL as Any, "baseURL:", readAccessURL as Any)

        if let fileURL = fileURL, let readAccessURL = readAccessURL {
            webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessURL)
        } else if let html = html {
            webView.loadHTMLString(html, baseURL: readAccessURL)
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
    }
}

struct MessagesView: View {
    let topic: Topic
    let currentUrl: String
    let curPage: Int
    let maxPage: Int

    @State private var page: Int
    @State private var fileURL: URL?
    @State private var cacheURL: URL?
    @State private var errorMessage: String?
    @State private var anchor: String?
    @State private var initialScroll: WebView.InitialScroll?
    @State private var isPresentingAddMessage = false
    @State private var isPresentingComposer = false
    @State private var replyText: String = ""
    @State private var isSendingReply = false
    @State private var isComposerMinimized = false
    @State private var animateLoadingSpinner = false

    init(topic: Topic, currentUrl: String, curPage: Int, maxPage: Int) {
        self.topic = topic
        self.currentUrl = currentUrl
        self.curPage = curPage
        self.maxPage = maxPage
        self._page = State(initialValue: curPage)

        // extraire l’ancre (#xxxx) si présente
        if let url = URL(string: currentUrl), let fragment = url.fragment {
            self._anchor = State(initialValue: fragment)
            print("INIT extracted anchor:", fragment)
        }
    }

    private func urlForPage(_ page: Int) -> String {
        guard var comps = URLComponents(string: currentUrl) else { return currentUrl }
        var queryItems = comps.queryItems ?? []
        if let index = queryItems.firstIndex(where: { $0.name == "page" }) {
            queryItems[index].value = "\(page)"
        } else {
            queryItems.append(URLQueryItem(name: "page", value: "\(page)"))
        }
        comps.queryItems = queryItems
        // ⚠️ On ne garde pas le fragment quand on change de page
        comps.fragment = nil
        return comps.string ?? currentUrl
    }

    private func loadPage(_ page: Int) {
        let url = urlForPage(page)
        print("loadPage(\(page)) url:", url, "current anchor:", self.anchor as Any)
        let controller = MessagesTableViewController()
        controller.fetchContent(forTopicURL: url) { html, error in
            DispatchQueue.main.async {
                if let error {
                    self.errorMessage = error.localizedDescription
                } else if let html {
                    let offlineStorage = OfflineStorage.shared()
                    let createdFileURL = offlineStorage!.createHtmlFileInCache(for: nil, withContent: html)
                    let cacheDirectoryURL = offlineStorage!.cacheURL()

                    self.fileURL = createdFileURL
                    self.cacheURL = cacheDirectoryURL
                    self.page = page

                    // Ne pas annuler l’ancre ici pour permettre le scroll après chargement
                    // self.anchor = nil
                }
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
        } else if let fileURL = fileURL, let cacheURL = cacheURL {
            WebView(fileURL: fileURL, readAccessURL: cacheURL, anchor: anchor, initialScroll: initialScroll)
                .id(page) // force a new WKWebView per page
                .ignoresSafeArea()
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
                                isPresentingComposer = true
                            } label: {
                                Label("Répondre", systemImage: "pencil")
                            }
                            if page > 1 {
                                Button {
                                    // Go to first page: start at top
                                    self.anchor = nil
                                    self.initialScroll = .top
                                    loadPage(1)
                                } label: {
                                    Label("Première page", systemImage: "backward.end.alt")
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
                            if maxPage > 1 {
                                Button {
                                    print("log")
                                } label: {
                                    Label("Page numéro...", systemImage: "ellipsis.circle")
                                }
                            }
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
                            Divider()
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
                }
                .sheet(isPresented: $isPresentingComposer) {
                    NavigationStack {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Répondre à \(topic._aTitle ?? "ce sujet")")
                                .font(.headline)

                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $replyText)
                                    .textInputAutocapitalization(.sentences)
                                    .autocorrectionDisabled(false)
                                    .frame(minHeight: 180)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.secondary.opacity(0.3))
                                    )

                                if replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("Saisissez votre réponse…")
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 8)
                                        .padding(.leading, 5)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .padding()
                        .navigationTitle("Nouvelle réponse")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Annuler") {
                                    isPresentingComposer = false
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button {
                                    isSendingReply = true
                                    ReplyService.shared.sendReply(text: replyText, topic: topic, currentUrl: currentUrl) { success in
                                        DispatchQueue.main.async {
                                            isSendingReply = false
                                            if success {
                                                isPresentingComposer = false
                                                // Refresh current page after sending
                                                loadPage(page)
                                            }
                                        }
                                    }
                                } label: {
                                    if isSendingReply {
                                        ProgressView()
                                    } else {
                                        Text("Envoyer")
                                    }
                                }
                                .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingReply)
                            }
                            ToolbarItem(placement: .bottomBar) {
                                Button {
                                    // Minimize: keep text, close sheet, show floating resume button
                                    isComposerMinimized = true
                                    isPresentingComposer = false
                                } label: {
                                    Label("Mettre de côté", systemImage: "arrow.down.right.and.arrow.up.left")
                                }
                            }
                        }
                    }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled(false)
                    .onDisappear {
                        // If the sheet was dismissed by swipe down (not by Cancel/Send),
                        // and we still have content or were composing, treat it as "Mettre de côté".
                        if !isPresentingComposer && !isComposerMinimized && !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            isComposerMinimized = true
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isComposerMinimized {
                        Button {
                            isPresentingComposer = true
                            isComposerMinimized = false
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.pencil")
                                Text("Reprendre")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                            .shadow(radius: 3)
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 24)
                    }
                }
                .onAppear {
                    loadPage(page)
                }
        } else {
            VStack(spacing:20) {
                //ProgressView()
                SpinnerLoading().fixedSize()
                Text("Chargement…")
                    .font(.title2)
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
                
            }
        }
    }
}

struct SpinnerLoading: View {

    var outerColor = Color.gray
    var innerColor = Color.cyan
    
    @State private var isAnimating = false

    var body: some View {

        GeometryReader { proxy in
            ZStack {
                self.trimmedCircle(color: self.outerColor, clockwise: true, scale: 1.0, proxy: proxy)
                self.trimmedCircle(color: self.innerColor, clockwise: false, scale: 0.75, proxy: proxy)
            }
        }
        .frame(idealWidth: 30, idealHeight: 30)
        .onAppear { self.isAnimating = true }

    }

    private func trimmedCircle(color: Color, clockwise: Bool, scale: CGFloat, proxy: GeometryProxy) -> some View {

        let start: Double = clockwise ? 360 : 0
        let end: Double = clockwise ? 0 : 360
        let borderWidth = min(proxy.size.width, proxy.size.height) / 14

        return Circle()
            .inset(by: borderWidth / 2)
            .scale(scale)
            .trim(from: 0.1, to: 0.9)
            .stroke(color, lineWidth: borderWidth)
            .rotationEffect(.degrees(isAnimating ? start : end))
            .animation(repeatingAnimation)

    }

    private let repeatingAnimation = Animation
        .linear(duration: 1.0)
        .repeatForever(autoreverses: false)
}
