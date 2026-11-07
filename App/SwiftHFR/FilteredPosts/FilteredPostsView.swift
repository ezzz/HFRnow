import HFRModels
import SwiftUI

// Port of HFRswift/Swift/Favorites.swift (FavoritePostFilterProgressBanner, FavoritePostFilterNavigationTarget) and of
// HFRswift/Swift/MessagesView.swift (the filter mode: subtitle, "Résultats suivants" bottom bar) @ 2440d79.
// Differences: the filtered posts open in a sheet over the list or the reader, not pushed on the list's stack (the entry
// points are two, and a sheet works in every layout); "Résultats suivants" can be cancelled and says what it reads; links
// open in the in-app browser (a forum link does not open a reader from here yet).
// LOT-185: "Résultats suivants" is a `safeAreaBar` with `.glassProminent`, not legacy's `.bottomBar` toolbar item (it holds a
// state line, a hint and Cancel); the banner is glass; GAP row pending #545.

/// Shows the progress banner, the filtered posts sheet and the failure alert of `model` over its content.
private struct FilteredPostsPresentation: ViewModifier {
    @Bindable var model: FilteredPostsModel
    let reader: ReaderServices

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                // With the sheet open the banner lives in the sheet.
                if model.result == nil, model.bannerText != nil {
                    FilteredPostsBanner(model: model).padding(.horizontal).padding(.bottom, 4)
                }
            }
            .sheet(isPresented: Binding(get: { model.result != nil }, set: { if !$0 { model.closeResult() } })) {
                NavigationStack { FilteredPostsView(model: model, services: reader) }
            }
            // With the sheet open the alert is presented by the sheet's content (a view cannot present both).
            .filteredPostsAlert(model, shown: model.result == nil)
    }
}

extension View {
    /// The "Filtre impossible" alert of `model`, when `shown`.
    fileprivate func filteredPostsAlert(_ model: FilteredPostsModel, shown: Bool) -> some View {
        alert(
            "Filtre impossible",
            isPresented: Binding(get: { shown && model.errorMessage != nil }, set: { if !$0 { model.dismissError() } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Erreur inconnue.")
        }
    }

    /// Adds the post filter's banner, result sheet and error alert, driven by `model`.
    func filteredPosts(_ model: FilteredPostsModel, reader: ReaderServices) -> some View {
        modifier(FilteredPostsPresentation(model: model, reader: reader))
    }
}

/// "N posts | page X/Y" with a cancel button while a run reads pages, or an information with "OK" (legacy
/// `FavoritePostFilterProgressBanner`, `Favorites.swift:1099-1135`).
struct FilteredPostsBanner: View {
    let model: FilteredPostsModel

    var body: some View {
        HStack(spacing: 10) {
            if model.statusMessage == nil {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "info.circle").font(.footnote).foregroundStyle(.secondary)
            }
            Text(model.bannerText ?? "").font(.footnote).lineLimit(1).monospacedDigit()
            Spacer(minLength: 8)
            if model.statusMessage == nil {
                Button("Annuler") { model.cancel() }.font(.footnote.weight(.semibold))
            } else {
                Button("OK") { model.dismissStatus() }.font(.footnote.weight(.semibold))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        // Legacy hid an information after 3 seconds.
        .task(id: model.statusMessage) {
            guard model.statusMessage != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { model.dismissStatus() }
        }
    }
}

/// The kept posts of one batch, read-only, with "Résultats suivants" at the bottom.
struct FilteredPostsView: View {
    let model: FilteredPostsModel
    let services: ReaderServices
    @State private var controller: ReaderWebController?
    @State private var document: ReaderDocument?
    @State private var readyToken: Int?
    /// The web view could not show the document (issue #566): a retry replaces the spinner.
    @State private var failed = false
    @State private var nextToken = 0
    @State private var external: ExternalLink?
    @State private var video: VideoItem?
    /// The open image viewer (LOT-109): the shared `reader.js` swallows a picture's tap, so this reader must open it.
    @State private var viewer: ImageViewerModel?
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            if let controller {
                ReaderWebView(controller: controller, document: document, scrollRequest: nil)
                    .opacity(readyToken == nil ? 0 : 1)
                    .accessibilityHidden(readyToken == nil)
            }
            if readyToken == nil {
                if failed {
                    ContentUnavailableView {
                        Label("Affichage impossible", systemImage: "exclamationmark.triangle")
                    } actions: {
                        Button("Réessayer") { show(model.result) }
                    }
                } else {
                    ProgressView("Chargement des messages")
                }
            }
        }
        .navigationTitle(model.title)
        .navigationSubtitle(model.result?.subtitle ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Fermer") { model.closeResult() } }
        }
        .safeAreaBar(edge: .top) {
            if model.bannerText != nil { FilteredPostsBanner(model: model).padding(.horizontal).padding(.top, 4) }
        }
        .safeAreaBar(edge: .bottom) {
            if let result = model.result { NextBatchBar(model: model, result: result) }
        }
        .filteredPostsAlert(model, shown: model.result != nil)
        .sheet(item: $external) { link in SafariView(url: link.url).ignoresSafeArea() }
        .sheet(item: $video) { item in VideoPlayerSheet(embed: item.embed) }
        .fullScreenCover(item: $viewer) { ImageViewerView(model: $0) }
        .onAppear(perform: makeController)
        // A screen that comes back hands the document again: its load may have been stopped before it was ready (issue #566).
        .onAppear {
            controller?.resume()
            controller?.show(document)
        }
        // Only a new page of posts reloads the document: marking the topic finished keeps the scroll position.
        .onChange(of: model.result?.page, initial: true) { _, _ in show(model.result) }
        .onDisappear {
            // The viewer covers this screen: the page stays as it is, or its pending pictures would turn into links.
            guard viewer == nil else { return }
            controller?.stopLoading()
        }
    }

    private func show(_ result: FilteredPostsResult?) {
        guard let result else { return }
        nextToken += 1
        readyToken = nil
        failed = false
        document = ReaderDocument(
            token: nextToken,
            html: TopicHTMLBuilder.document(for: result.page, token: nextToken, options: services.settings.renderOptions()),
            anchor: nil, keepsScrollPosition: false
        )
    }

    private func makeController() {
        guard controller == nil else { return }
        let controller = ReaderWebController(
            imageFetcher: services.imageFetcher, autoLoadsThirdPartyImages: services.settings.autoLoadsThirdPartyImages
        )
        controller.events = ReaderWebController.Events(
            ready: { token in if token == document?.token { readyToken = token } },
            // A shown page whose reload after a crash failed twice is blank again: the retry replaces it (#566).
            failed: { token in
                guard token == document?.token else { return }
                readyToken = nil
                failed = true
            },
            link: { url in
                guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return }
                if services.settings.opensLinksInDefaultBrowser() { openURL(url) } else { external = ExternalLink(url: url) }
            },
            video: { post, index, token in
                guard token == document?.token,
                      let message = model.result?.page.messages.first(where: { $0.numreponse == post }),
                      message.content.embeds.indices.contains(index) else { return }
                video = VideoItem(embed: message.content.embeds[index])
            },
            image: { images, index, _ in
                viewer = ImageViewerModel(images: images, index: index, services: .live(fetcher: services.imageFetcher))
            }
        )
        self.controller = controller
    }
}

/// "Résultats suivants": says what it reads, and can be cancelled while it runs (the batch shown stays).
private struct NextBatchBar: View {
    let model: FilteredPostsModel
    let result: FilteredPostsResult

    var body: some View {
        VStack(spacing: 6) {
            if model.isAdvancing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Filtrage des pages suivantes…").font(.footnote)
                    Spacer()
                    Button("Annuler") { model.cancel() }
                }
            } else if result.isFinished {
                Text("Fin du sujet : plus aucun post à afficher.").font(.footnote).foregroundStyle(.secondary)
            } else {
                Button { model.showNextBatch() } label: {
                    Label("Résultats suivants", systemImage: "arrow.forward").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                if let hint = model.nextBatchHint {
                    Text(hint).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
