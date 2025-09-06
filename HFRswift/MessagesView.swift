//
//  MessagesView.swift
//  SuperHFRplus
//
//  Created by Bruno ARENE on 9/3/25.
//

import SwiftUI

/*struct WebView: UIViewRepresentable {
    let html: String
    func makeUIView(context: Context) -> WKWebView { WKWebView() }
    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }
}*/

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
        if let fileURL = fileURL, let readAccessURL = readAccessURL {
            // Charger depuis un fichier local
            webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessURL)
        } else if let html = html {
            // Charger depuis HTML string
            webView.loadHTMLString(html, baseURL: readAccessURL)
        }
    }
}
/*
struct MessagesView: View {
    let topic: Topic
    let currentUrl: String

    @State private var htmlContent = "<html><body>Chargement…</body></html>"
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage { Text("Erreur : \(errorMessage)").foregroundColor(.red) }
            else { WebView(html: htmlContent).ignoresSafeArea() }
        }
        .navigationTitle(topic._aTitle ?? "Messages")
        .onAppear {
            let controller = MessagesTableViewController()
            // ✅ Appel correct avec la completion
            controller.fetchContent(forTopicURL: currentUrl) { html, error in
                DispatchQueue.main.async {
                    if let error {
                        self.errorMessage = error.localizedDescription
                    } else if let html {
                        self.htmlContent = html
                    }
                }
            }
        }
    }
}*/

struct MessagesView: View {
    let topic: Topic
    let currentUrl: String
    
    @State private var fileURL: URL?
    @State private var cacheURL: URL?
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if let errorMessage {
                Text("Erreur : \(errorMessage)").foregroundColor(.red)
            } else if let fileURL = fileURL, let cacheURL = cacheURL {
                WebView(fileURL: fileURL, readAccessURL: cacheURL).ignoresSafeArea()
            } else {
                Text("Chargement…")
            }
        }
        .navigationTitle(topic._aTitle ?? "Messages")
        .onAppear {
            let controller = MessagesTableViewController()
            controller.fetchContent(forTopicURL: currentUrl) { html, error in
                DispatchQueue.main.async {
                    if let error {
                        self.errorMessage = error.localizedDescription
                    } else if let html {
                        // Créer le fichier HTML dans le cache
                        let offlineStorage = OfflineStorage.shared()
                        let createdFileURL = offlineStorage!.createHtmlFileInCache(for: nil, withContent: html)
                        let cacheDirectoryURL = offlineStorage!.cacheURL()
                        
                        self.fileURL = createdFileURL
                        self.cacheURL = cacheDirectoryURL
                        
                        print("fileURL: \(String(describing: createdFileURL))")
                        print("cacheURL: \(String(describing: cacheDirectoryURL))")
                    }
                }
            }
        }
    }
}



/*


struct MessagesView: UIViewControllerRepresentable {
    let topic: Topic
    let currentUrl: String

    func makeUIViewController(context: Context) -> MessagesTableViewController {
        let controller = MessagesTableViewController()

        controller.fetchContentForTopicURL(currentUrl) { html, error in
            if let error = error {
                print("Erreur fetchContent: \(error)")
            } else {
                print("HTML reçu: \(html ?? "")")
            }
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: MessagesTableViewController, context: Context) {
        // mise à jour si besoin
    }
}

struct WebContentView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        return WKWebView()
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.loadHTMLString(html, baseURL: nil)
    }
}

struct MessagesFullScreenView: View {
    let topic: Topic
    @Environment(\.dismiss) var dismiss

    @State private var htmlContent: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let html = htmlContent {
                WebContentView(html: html)
                    .ignoresSafeArea()
            } else if let error = errorMessage {
                VStack {
                    Text("Erreur")
                        .font(.title)
                        .padding()
                    Text(error)
                        .foregroundColor(.red)
                    Button("Fermer") { dismiss() }
                        .padding()
                }
            } else {
                ProgressView("Chargement...")
            }
        }
        .onAppear {
            loadContent()
        }
    }

    private func loadContent() {
        MessagesTableViewController.fetchContentForTopicURL(topic.aURL) { html, error in
            if let error = error {
                errorMessage = error.localizedDescription
            } else {
                htmlContent = html
            }
        }
    }
}
*/
