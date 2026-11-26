import HFRModels
import SwiftUI
import UIKit

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
                ThemedNavigationStack { FilteredPostsView(model: model, services: reader) }
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

private extension View {
    /// A bordered glass capsule, not the text box of a plain button (#1152; legacy `Favorites.swift:1215-1255`).
    func bannerButton() -> some View {
        buttonStyle(.glass)
            .controlSize(.small)
            .font(.footnote.weight(.semibold))
    }
}

/// "N posts | page X/Y" with a cancel button while a run reads pages, or an information with "OK" (legacy
/// `FavoritePostFilterProgressBanner`, `Favorites.swift:1099-1135`).
struct FilteredPostsBanner: View {
    let model: FilteredPostsModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 10) {
            if model.statusMessage == nil {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "info.circle").font(.footnote).foregroundStyle(.secondary)
            }
            Text(model.bannerText ?? "").font(.footnote).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1).monospacedDigit()
            Spacer(minLength: 8)
            if model.statusMessage == nil {
                Button("Annuler") { model.cancel() }.bannerButton()
            } else {
                Button("OK") { model.dismissStatus() }.bannerButton()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        // The information goes by itself on the model's timer, never under VoiceOver (#1152; legacy hid it after 3 s).
    }
}

/// The kept posts of one batch, read-only, with "Résultats suivants" at the bottom. Each post has the reader's report and block
/// entries (LOT-159, `FilteredPostsMenuModel`).
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
    /// The message and author menus (LOT-159).
    @State private var menus: FilteredPostsMenuModel?
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
                    ProgressView()
                }
            }
        }
        .navigationTitle(model.title)
        .navigationSubtitle(model.result?.subtitle ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            SheetCloseToolbarItem { model.closeResult() }
        }
        .safeAreaBar(edge: .top) {
            if model.bannerText != nil { FilteredPostsBanner(model: model).padding(.horizontal).padding(.top, 4) }
        }
        .safeAreaBar(edge: .bottom) {
            if let result = model.result { NextBatchBar(model: model, result: result) }
        }
        .filteredPostsAlert(model, shown: model.result != nil)
        .overlay(alignment: .bottom) { if let menus { ReaderMenuFeedbackBanner(model: menus) } }
        .onChange(of: menus?.menuFeedbackSerial) { ReaderAccessibility.announce(menus?.menuFeedback) }
        .modifier(ReaderAlertFlow(alerts: menus?.alerts))
        // A blocked or allowed author: the batch is built again with the lists as they are now, where it was scrolled to. The
        // first value (the menus made with the first document) is no change.
        .onChange(of: menus?.listsRevision) { old, _ in if old != nil { rebuild(model.result) } }
        .signInToBlockSheet(isPresented: Binding(get: { menus?.wantsSignIn ?? false }, set: { menus?.wantsSignIn = $0 }))
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
        document = menuModel().document(for: result, token: nextToken, keepsScrollPosition: false)
    }

    /// The batch on screen built again (a list change): the web view stays shown and keeps its position, as the reader's.
    private func rebuild(_ result: FilteredPostsResult?) {
        guard let result, readyToken != nil else { return show(result) }
        nextToken += 1
        document = menuModel().document(for: result, token: nextToken, keepsScrollPosition: true)
    }

    /// The menus, made by whichever comes first of the controller and the first document (both need them).
    private func menuModel() -> FilteredPostsMenuModel {
        if let menus { return menus }
        let openURL = self.openURL
        let made = FilteredPostsMenuModel(
            services: services, copy: { UIPasteboard.general.string = $0.absoluteString }, openMail: { openURL($0) }
        )
        menus = made
        return made
    }

    private func makeController() {
        guard controller == nil else { return }
        let menus = menuModel()
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
            menu: { [weak controller, weak menus] post, source, anchor, token in
                guard token == document?.token, let result = model.result, let controller, let menus,
                      let menu = menus.menu(post: post, source: source, anchor: anchor, in: result) else { return }
                controller.messageMenu.present(
                    menu, topInset: controller.obscuredInsets.top,
                    pick: { action in Task { await menus.perform(action, in: menu) } }, closed: {}
                )
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
