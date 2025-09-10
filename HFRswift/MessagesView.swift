//
//  MessagesView.swift
//  SuperHFRplus
//
//  Created by Bruno ARENE on 9/3/25.
//

import SwiftUI

struct WebView: UIViewRepresentable {
    let html: String?
    let fileURL: URL?
    let readAccessURL: URL?
    
    // Initializer pour HTML string (existant)
    init(html: String, baseURL: URL? = nil) {
        self.html = html
        self.fileURL = nil
        self.readAccessURL = baseURL
    }
    
    // Nouveau initializer pour fichier local
    init(fileURL: URL, readAccessURL: URL) {
        self.html = nil
        self.fileURL = fileURL
        self.readAccessURL = readAccessURL
    }
    
    func makeUIView(context: Context) -> WKWebView {
        return WKWebView()
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        print("updateUIView called with fileURL:", fileURL?.absoluteString ?? "nil")
        if let fileURL = fileURL, let readAccessURL = readAccessURL {
            // Charger depuis un fichier local
            webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessURL)
        } else if let html = html {
            // Charger depuis HTML string
            webView.loadHTMLString(html, baseURL: readAccessURL)
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
    
    init(topic: Topic, currentUrl: String, curPage: Int, maxPage: Int) {
        self.topic = topic
        self.currentUrl = currentUrl
        self.curPage = curPage
        self.maxPage = maxPage
        self._page = State(initialValue: curPage)
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
                }
            }
        }
    }
    
    var body: some View {
        Group {
            if let errorMessage {
                Text("Erreur : \(errorMessage)").foregroundColor(.red)
            } else if let fileURL = fileURL, let cacheURL = cacheURL {
                WebView(fileURL: fileURL, readAccessURL: cacheURL)
                    .id(page) // 🔑 force la recréation quand l’URL change
                    .ignoresSafeArea()
                    .simultaneousGesture(
                        DragGesture().onEnded { value in
                                let horizontal = value.translation.width
                                let vertical = value.translation.height
                                
                                // seuils
                                let minDistance: CGFloat = 120
                                let maxVerticalRatio: CGFloat = 0.5 // tolérance verticale (50%)
                                
                                if abs(horizontal) > minDistance && abs(vertical) < abs(horizontal) * maxVerticalRatio {
                                    if horizontal < 0, page < maxPage {
                                        // Swipe gauche → page suivante
                                        loadPage(page + 1)
                                    } else if horizontal > 0, page > 1 {
                                        // Swipe droite → page précédente
                                        loadPage(page - 1)
                                    }
                                }
                            }
                    )
            } else {
                Text("Chargement…")
            }
        }
        .navigationTitle("\(page)/\(maxPage)")
        .font(.caption2)//\(topic._aTitle ?? "Messages") []")
        .onAppear {
            loadPage(page)
        }
    }
}
