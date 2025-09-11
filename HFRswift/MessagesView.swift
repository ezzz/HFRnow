//
//  MessagesView.swift
//  SuperHFRplus
//
//  Created by Bruno ARENE on 9/3/25.
//

import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let html: String?
    let fileURL: URL?
    let readAccessURL: URL?
    var anchor: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.anchor = anchor

        if let fileURL = fileURL, let readAccessURL = readAccessURL {
            webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessURL)
        } else if let html = html {
            webView.loadHTMLString(html, baseURL: readAccessURL)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        var anchor: String?

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let anchor = anchor else { return }

            // Essayons d'abord par id, sinon par name
            let js = """
            (function() {
                var el = document.getElementById('\(anchor)');
                if (!el) {
                    var els = document.getElementsByName('\(anchor)');
                    if (els.length > 0) el = els[0];
                }
                if (el) { el.scrollIntoView({behavior: 'smooth'}); }
            })();
            """

            webView.evaluateJavaScript(js, completionHandler: { result, error in
                if let error = error {
                    print("Anchor scroll JS error:", error.localizedDescription)
                }
            })
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

    init(topic: Topic, currentUrl: String, curPage: Int, maxPage: Int) {
        self.topic = topic
        self.currentUrl = currentUrl
        self.curPage = curPage
        self.maxPage = maxPage
        self._page = State(initialValue: curPage)

        // extraire l’ancre (#xxxx) si présente
        if let url = URL(string: currentUrl), let fragment = url.fragment {
            self._anchor = State(initialValue: fragment)
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

                    // après le premier chargement on ignore l’ancre
                    self.anchor = nil
                }
            }
        }
    }

    var body: some View {
        Group {
            if let errorMessage {
                Text("Erreur : \(errorMessage)").foregroundColor(.red)
            } else if let fileURL = fileURL, let cacheURL = cacheURL {
                WebView(fileURL: fileURL, readAccessURL: cacheURL, anchor: anchor)
                    .id(page) // 🔑 force un nouveau WKWebView par page
                    .ignoresSafeArea()
                    .simultaneousGesture(
                        DragGesture().onEnded { value in
                            let horizontal = value.translation.width
                            let vertical = value.translation.height

                            // seuils pour éviter les faux positifs
                            let minDistance: CGFloat = 120
                            let maxVerticalRatio: CGFloat = 0.5

                            if abs(horizontal) > minDistance && abs(vertical) < abs(horizontal) * maxVerticalRatio {
                                if horizontal < 0, page < maxPage {
                                    loadPage(page + 1)
                                } else if horizontal > 0, page > 1 {
                                    loadPage(page - 1)
                                }
                            }
                        }
                    )
            } else {
                Text("Chargement…")
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("\(topic._aTitle ?? "Messages") [\(page)/\(maxPage)]")
                    .font(.caption2) // texte réduit au minimum
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .onAppear {
            loadPage(page)
        }
    }
}

