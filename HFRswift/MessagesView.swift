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

    init(html: String? = nil, fileURL: URL? = nil, readAccessURL: URL? = nil, anchor: String? = nil) {
        self.html = html
        self.fileURL = fileURL
        self.readAccessURL = readAccessURL
        self.anchor = anchor
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

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let anchor = anchor else { return }

            print("WKWebView didFinish. anchor =", anchor as Any, "url:", webView.url?.absoluteString ?? "nil")

            // Probe: check if element exists by id or name
            let probe = """
            (function(a){
              var byId = document.getElementById(a);
              var byName = document.getElementsByName(a)[0];
              return 'probe byId='+(!!byId)+' byName='+(!!byName)+' a='+a;
            })('\(anchor)')
            """
            webView.evaluateJavaScript(probe) { result, error in
                print("Anchor probe:", result ?? "nil", "error:", error?.localizedDescription ?? "none")
            }

            // Timed scroll with fallback to location.hash
            let js = """
            setTimeout(function(){
              var a = '\(anchor)';
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
                        Text("\(topic._aTitle ?? "Messages") [\(page)/\(maxPage)]")
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .onAppear {
                    loadPage(page)
                }
        } else if let fileURL = fileURL, let cacheURL = cacheURL {
            WebView(fileURL: fileURL, readAccessURL: cacheURL, anchor: anchor)
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
                                loadPage(page + 1)
                            } else if horizontal > 0, page > 1 {
                                loadPage(page - 1)
                            }
                        }
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("\(topic._aTitle ?? "Messages") [\(page)/\(maxPage)]")
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .onAppear {
                    loadPage(page)
                }
        } else {
            Text("Chargement…")
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("\(topic._aTitle ?? "Messages") [\(page)/\(maxPage)]")
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .onAppear {
                    loadPage(page)
                }
        }
    }
}

