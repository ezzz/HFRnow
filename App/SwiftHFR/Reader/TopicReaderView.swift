import HFRModels
import SafariServices
import SwiftUI
import WebKit

/// The detail column: one topic page in a web view, page navigation, refresh, links and video players on tap.
struct TopicReaderView: View {
    let model: TopicReaderModel
    let services: ReaderServices
    @State private var controller: ReaderWebController?
    @State private var external: ExternalLink?
    @State private var video: VideoItem?
    @State private var askingPage = false
    @State private var pageText = ""

    var body: some View {
        ZStack {
            if let controller {
                ReaderWebView(controller: controller, document: model.document, scrollRequest: model.scrollRequest)
                    .opacity(model.hasShownDocument ? 1 : 0)
                    .accessibilityHidden(!model.hasShownDocument)
            }
            overlay
        }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            if let error = model.error, model.page != nil {
                LoadFailureBanner(error: error, retry: model.retry)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.page != nil { ReaderPageBar(model: model, askPage: askForPage) }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await model.refresh() } } label: { Label("Actualiser", systemImage: "arrow.clockwise") }
                    .disabled(model.isLoading)
            }
        }
        .alert("Aller à la page", isPresented: $askingPage) {
            TextField("Page", text: $pageText).keyboardType(.numberPad)
            Button("Annuler", role: .cancel) {}
            Button("Aller") {
                if let number = Int(pageText) { Task { await model.goToPage(number) } }
            }
        } message: {
            if let page = model.page { Text("Entre 1 et \(page.maxPage)") }
        }
        .sheet(item: $external) { link in SafariView(url: link.url).ignoresSafeArea() }
        .sheet(item: $video) { item in VideoPlayerSheet(embed: item.embed) }
        .onAppear(perform: makeController)
        .task { await model.onAppear() }
        .onDisappear {
            model.cancel()
            controller?.stopLoading()
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if model.page == nil {
            if let error = model.error {
                LoadFailureView(error: error, retry: model.retry)
            } else {
                ProgressView("Chargement des messages")
            }
        } else if let page = model.page, page.messages.isEmpty {
            ContentUnavailableView {
                Label("Aucun message", systemImage: "text.bubble")
            } description: {
                Text(page.notice ?? "Cette page ne contient aucun message.")
            } actions: {
                Button("Actualiser") { Task { await model.refresh() } }
            }
        } else if !model.hasShownDocument {
            ProgressView("Chargement des messages")
        }
    }

    private func askForPage() {
        pageText = ""
        askingPage = true
    }

    private func makeController() {
        guard controller == nil else { return }
        let controller = ReaderWebController(
            imageFetcher: services.imageFetcher, autoLoadsThirdPartyImages: services.settings.autoLoadsThirdPartyImages
        )
        controller.events = ReaderWebController.Events(
            ready: { [model] token in model.documentDidBecomeReady(token: token) },
            link: { [model] url in
                switch model.action(forLink: url) {
                case .reader(let target): Task { await model.open(target) }
                case .external(let url): external = ExternalLink(url: url)
                case .ignored: break
                }
            },
            video: { [model] post, index, token in
                if let embed = model.video(post: post, index: index, token: token) { video = VideoItem(embed: embed) }
            }
        )
        self.controller = controller
    }
}

/// What the reader shares across pages: the image client and the settings it reads.
struct ReaderServices: Sendable {
    /// Images through the cookie-less client.
    let imageFetcher: ReaderImageFetcher
    /// Image mode and display choices.
    let settings: ReaderSettings
}

/// Previous / next page, first / last, and "page N / M" which asks for a page number.
private struct ReaderPageBar: View {
    let model: TopicReaderModel
    let askPage: () -> Void

    var body: some View {
        HStack {
            Button { Task { await model.goToPage(1) } } label: { Image(systemName: "backward.end") }
                .disabled(!model.canGoToPrevious || model.isLoading)
                .accessibilityLabel("Première page")
            Button { Task { await model.goToPage((model.page?.currentPage ?? 1) - 1) } } label: { Image(systemName: "chevron.left") }
                .disabled(!model.canGoToPrevious || model.isLoading)
                .accessibilityLabel("Page précédente")
            Spacer()
            if model.isLoading {
                ProgressView()
            } else if let page = model.page {
                Button(action: askPage) { Text("Page \(page.currentPage) / \(page.maxPage)").monospacedDigit() }
                    .accessibilityHint("Choisir une page")
            }
            Spacer()
            Button { Task { await model.goToPage((model.page?.currentPage ?? 1) + 1) } } label: { Image(systemName: "chevron.right") }
                .disabled(!model.canGoToNext || model.isLoading)
                .accessibilityLabel("Page suivante")
            Button { Task { await model.goToPage(model.page?.maxPage ?? 1) } } label: { Image(systemName: "forward.end") }
                .disabled(!model.canGoToNext || model.isLoading)
                .accessibilityLabel("Dernière page")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// Hosts the controller's web view and hands it the model's document and scroll requests.
private struct ReaderWebView: UIViewRepresentable {
    let controller: ReaderWebController
    let document: ReaderDocument?
    let scrollRequest: ScrollRequest?

    func makeUIView(context: Context) -> WKWebView { controller.webView }

    func updateUIView(_ webView: WKWebView, context: Context) {
        controller.show(document)
        controller.apply(scrollRequest)
    }
}

private struct ExternalLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct VideoItem: Identifiable {
    let embed: MessageEmbed
    var id: String { embed.embedURL.absoluteString }
}

/// A web link opened outside the reader, in Safari's own view (LOT-071 T8): Safari's data, not the app's.
private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
