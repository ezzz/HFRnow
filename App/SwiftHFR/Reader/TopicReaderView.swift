import HFRModels
import SwiftUI
import WebKit

// Port of HFRswift/Swift/MessagesView.swift (MessagesView: bottom page toolbar, Safari view, composer sheet) @ 2440d79. Differences:
// the page controls are the legacy ‹ › with a "N / M" page menu, the same page items also sit in the "…" overflow, with new labels
// (`ReaderPageControls`, LOT-186, #582); the page
// runs under the glass bars; videos on tap (GAP-058, 060; UXD-10). The tab bar is hidden while a topic is open, as legacy does
// (`.toolbar(.hidden, for: .tabBar)`, Favorites.swift:807, MessagesView.swift:3256; GAP-008, UXD-02), but only in compact width (the
// split collapsed) and only when the reader's tab is the selected one: list and reader side by side (Pro Max landscape, iPad) keep the
// bar, the only way to switch tabs there. The full-screen Plus search and offline readers keep it in regular width too (see GAP-008).
/// Whether the reader's root tab is the selected one; `RootTabsView` sets it per tab (default true outside the tab bar).
private struct IsSelectedRootTabKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var isSelectedRootTab: Bool {
        get { self[IsSelectedRootTabKey.self] }
        set { self[IsSelectedRootTabKey.self] = newValue }
    }
}

/// The tab bar rule of the reader (GAP-008, UXD-02): hidden in compact width while its own tab is selected, so a reader left
/// open in another tab (rotation, tab switch) never hides the shared bar.
enum ReaderTabBar {
    nonisolated static func visibility(sizeClass: UserInterfaceSizeClass?, isSelectedTab: Bool) -> Visibility {
        sizeClass == .compact && isSelectedTab ? .hidden : .automatic
    }
}

/// The detail column: one topic page in a web view, page navigation, refresh, links, video players on tap and the reply
/// sheet. A followed forum link pushes another reader (legacy `MessagesView.openInternalTopic`); its host wraps it in a
/// `NavigationStack` (`ReaderColumn`, `MessageReaderColumn`).
struct TopicReaderView: View {
    let model: TopicReaderModel
    let services: ReaderServices
    /// The current account's composer; nil when logged out.
    var composer: ComposerServices?
    /// Starts the post filter on this topic (LOT-114); nil hides the menu entry.
    var onFilterPosts: (() -> Void)?
    /// A filter run is reading pages: the menu entry is disabled meanwhile.
    var filterIsBusy = false
    /// Told how "Marquer comme non lu" ended (LOT-127): the conversation's list; nil when no list hosts this reader.
    var onMarkUnread: MarkUnreadHost?
    @State private var controller: ReaderWebController?
    /// This view instance, for the model: another view on the same model must not stop this one's load (issue #566).
    @State private var viewerID = ReaderViewerID.next()
    /// The offline save of this topic (LOT-139); nil without offline services (the offline reader, previews).
    @State private var saver: OfflineSaveModel?
    @State private var external: ExternalLink?
    @State private var video: VideoItem?
    /// The open image viewer (LOT-109); a fresh model per tap.
    @State private var viewer: ImageViewerModel?
    @State private var profile: UserProfileModel?
    /// The author menu's MP composer and handlers (issue #595).
    @State private var authorMenu = AuthorMenuFlow()
    @State private var askingPage = false
    @State private var pageText = ""
    /// The swipe and reply button settings, and the display settings, followed while the reader is on screen (#750).
    @State private var settings = ReaderSettingsWatch()
    /// "Editer" and "Supprimer" of the message menu (LOT-088); nil until the menu is installed, and logged out.
    @State private var writes: MessageWriteModel?
    /// "Alerter" of the message menu (LOT-135); nil until the menu is installed.
    @State private var alerts: ModeratorAlertModel?
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.isSelectedRootTab) private var isSelectedTab

    var body: some View {
        ZStack {
            if let controller {
                // The page runs under the bars and banners (HIG Layout: extend content under the bars, LOT-186); what they cover
                // is the safe area this full-height reader ignores, handed to the web view.
                ReaderUnderBars { obscured in
                    ReaderWebView(
                        controller: controller, document: model.document, scrollRequest: model.scrollRequest,
                        obscured: obscured
                    )
                }
                .opacity(model.hasShownDocument ? 1 : 0)
                .accessibilityHidden(!model.hasShownDocument)
                .simultaneousGesture(pageSwipe, including: settings.swipesPages ? .all : .none)
            }
            overlay
        }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(ReaderTabBar.visibility(sizeClass: sizeClass, isSelectedTab: isSelectedTab), for: .tabBar)
        .safeAreaInset(edge: .top) {
            if let error = model.error, model.page != nil, model.hasShownDocument {
                // "Réessayer" does nothing under an open composer (#653): dimmed, as "Actualiser".
                LoadFailureBanner(error: error, retry: retry).disabled(model.suspendsPageInteractions)
            }
        }
        .modifier(ReaderReplyFlow(model: model, composer: composer))
        .modifier(ReaderEditFlow(writes: writes))
        .modifier(ReaderComposerGuard(model: model, controller: controller, isEditing: writes?.editor != nil))
        .modifier(ReaderAlertFlow(alerts: alerts))
        .modifier(ReaderSearchFlow(model: model, composer: composer))
        .modifier(ReaderPollFlow(model: model, composer: composer))
        .modifier(ReaderMarkUnreadFlow(model: model, actions: services.flagActions, host: onMarkUnread))
        .offlineSave(model: model, saver: saver)
        .toolbar {
            ReaderPageControls(model: model, askPage: askForPage, replySymbol: replySymbol)
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await refresh() } } label: { Label("Actualiser", systemImage: "arrow.clockwise") }
                    .disabled(model.isLoading || model.suspendsPageInteractions)
            }
            // No "…" entry under an open composer (#653): a disabled one would still open the overflow.
            if let onFilterPosts, !model.suspendsPageInteractions {
                ToolbarItem(placement: .secondaryAction) {
                    Button(action: onFilterPosts) {
                        Label("Filtrer les posts", systemImage: "line.3.horizontal.decrease")
                    }
                    .disabled(filterIsBusy)
                }
            }
            // The system "…" overflow: legacy `pageChoiceMenuItems` after the other actions, only past one page (#582).
            if let page = model.page, page.maxPage > 1, !model.suspendsPageInteractions {
                ToolbarItemGroup(placement: .secondaryAction) {
                    // A Section, so the separator before the page items is explicit (legacy `Divider()`, :4718-4720).
                    Section { ReaderPageMenuItems(model: model, maxPage: page.maxPage, askPage: askForPage) }
                }
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
        .overlay { ReaderMessageMenuAnchor(model: model) }
        .overlay(alignment: .bottom) { menuFeedbackBanner }
        .sheet(item: $external) { link in SafariView(url: link.url).ignoresSafeArea() }
        .sheet(item: $video) { item in VideoPlayerSheet(embed: item.embed) }
        .fullScreenCover(item: $viewer) { ImageViewerView(model: $0) }
        .sheet(item: $profile, onDismiss: model.applyDisplaySettings, content: { UserProfileView(model: $0, services: services) })
        .modifier(ReaderAuthorMenuSheet(flow: authorMenu, model: model))
        .navigationDestination(item: linkedReader) { linked in
            // A private conversation reached from a topic offers no reply: MP replies are LOT-128's (no composer in Messages).
            TopicReaderView(model: linked.model, services: services, composer: linked.model.isPrivateConversation ? nil : composer)
        }
        .appScreenBackground().onAppear(perform: makeController)
        // A view that comes back hands the document again: its load may have been stopped before it was ready (issue #566).
        .onAppear {
            controller?.viewAppeared()
            controller?.show(model.document)
        }
        .onAppear {
            if saver == nil, let offline = services.offline { saver = OfflineSaveModel(store: offline.store, fetcher: offline.fetcher) }
        }
        // The selection menu offers its quotes once the page has an answer form (and not at all logged out).
        .onChange(of: model.canQuote) { controller?.offersSelectionQuote = model.offersSelectionQuote }
        .modifier(ReaderAnnouncements(model: model))
        // The settings screen writes `UserDefaults`: a display setting changed there reaches the open reader at once.
        .onAppear { settings.start(services.settings, changed: model.displaySettingsHook) }
        .task {
            installMenuActions()
            await model.onAppear(viewer: viewerID)
        }
        .onDisappear {
            // Covered by the reader of a followed link: this page stays as it is, for the way back.
            // Same for the image viewer (a full-screen cover calls it): stopping would turn the pending pictures into links.
            guard model.linkedReader == nil, viewer == nil else { return }
            // The controller checks the window first (issue #750), and calls `leave()` back through `events.left`.
            if let controller { controller.viewDisappeared() } else { leave() }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if model.page == nil {
            if let error = model.error {
                LoadFailureView(error: error, retry: retry)
            } else {
                ProgressView("Chargement des messages")
            }
        } else if let page = model.page, page.messages.isEmpty {
            ContentUnavailableView {
                Label("Aucun message", systemImage: "text.bubble")
            } description: {
                Text(page.notice ?? "Cette page ne contient aucun message.")
            } actions: {
                Button("Actualiser") { Task { await refresh() } }
            }
        } else if !model.hasShownDocument {
            // The web view could not show the page (issue #566): a retry, never an endless spinner.
            if let error = model.error {
                LoadFailureView(error: error, retry: retry)
            } else {
                ProgressView("Chargement des messages")
            }
        }
    }

    @ViewBuilder
    private var menuFeedbackBanner: some View {
        if let feedback = model.menuFeedback {
            Text(feedback)
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 8)
                .task(id: model.menuFeedbackSerial) { [serial = model.menuFeedbackSerial] in
                    // A cancelled sleep (a newer confirmation, the view going away) must not clear anything.
                    do {
                        try await Task.sleep(for: .seconds(2))
                        model.clearMenuFeedback(serial: serial)
                    } catch {}
                }
        }
    }

    /// The legacy horizontal drag that changes the page, when the setting is on (read at the end of each drag).
    private var pageSwipe: some Gesture {
        DragGesture().onEnded { value in
            guard services.settings.swipesPages(), let page = model.page,
                  let swipe = PageSwipe.of(
                      translation: value.translation, predictedEnd: value.predictedEndTranslation,
                      page: page.currentPage, maxPage: page.maxPage
                  )
            else { return }
            Task { await model.swipe(swipe) }
        }
    }

    /// The reply button's symbol, nil when there is none: logged out, no answer form, or `reply_button_behavior` hidden;
    /// `forum` draws the pencil, `quick` the plus (legacy `replyButtonSystemImage`).
    private var replySymbol: String? {
        guard composer != nil, model.replyTarget != nil, settings.replyButton != .hidden else { return nil }
        return settings.replyButton == .forum ? "square.and.pencil" : "plus"
    }

    private var linkedReader: Binding<LinkedReader?> {
        Binding(
            get: { model.linkedReader.map(LinkedReader.init) },
            set: { if $0 == nil { model.closeLinkedReader() } }
        )
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
            failed: { [model] token in model.documentDidFail(token: token) },
            link: { [model] url in
                switch model.action(forLink: url, defaultBrowser: services.settings.opensLinksInDefaultBrowser()) {
                case .reader(let target): model.follow(target)
                // The hook holds the model weakly: the sheet outlives this tap (`UserProfileModel.onListsChanged`).
                case .profile(let memberID): profile = services.profileModel(memberID: memberID, listsChanged: model.displaySettingsHook)
                case .inAppBrowser(let url): external = ExternalLink(url: url)
                case .defaultBrowser(let url): openURL(url)
                case .ignored: break
                }
            },
            video: { [model] post, index, token in
                if let embed = model.video(post: post, index: index, token: token) { video = VideoItem(embed: embed) }
            },
            position: { [model] post, token in Task { await model.recordPosition(post: post, token: token) } },
            menu: { [model] post, source, anchor, token in
                Task { await model.openMenu(post: post, source: source, anchor: anchor, token: token) }
            },
            quote: { [model] post, text, bold, token in
                Task { await model.quoteSelection(post: post, text: text, bold: bold, token: token) }
            },
            image: { images, index, _ in
                // The controller already checked the document token (a stale page's tap never gets here).
                viewer = ImageViewerModel(images: images, index: index, services: .live(fetcher: services.imageFetcher))
            }, notice: { [model] in model.showMenuFeedback($0) },
            // Weak and through bindings, not `self`: the controller stores this closure, and `self`'s `@State` holds the
            // controller (LOT-087).
            left: { [weak controller, model, viewerID, covered = $viewer, saver = $saver, settings] in
                Self.leave(model: model, viewerID: viewerID, covered: covered.wrappedValue != nil) {
                    saver.wrappedValue?.leave()
                    settings.stop()
                    controller?.stopLoading()
                }
            },
            // On screen again with no `onAppear` (issue #750): the page, its load and the settings come back as `onAppear`
            // brings them.
            returned: { [weak controller, model, viewerID, settings, readerSettings = services.settings] in
                controller?.show(model.document)
                settings.start(readerSettings, changed: model.displaySettingsHook)
                Task { await model.onAppear(viewer: viewerID) }
            }
        )
        model.adopt(services, composer: composer)
        controller.offersSelectionQuote = model.offersSelectionQuote
        controller.ignoresPageTaps = model.suspendsPageInteractions
        self.controller = controller
    }
}

// Out of the struct body, which reached SwiftLint's `type_body_length` with LOT-135's handler.
extension TopicReaderView {
    /// "Réessayer" and "Actualiser" are tapped on screen: the web view shows what they load even if a lifecycle call stopped it
    /// (#643: "Actualiser does not recover it").
    private func retry() async {
        controller?.resume()
        await model.retry()
    }

    private func refresh() async {
        controller?.resume()
        await model.refresh()
    }

    /// The reader left the screen: its load, its offline save and its web view stop.
    private func leave() {
        Self.leave(model: model, viewerID: viewerID, covered: viewer != nil) {
            saver?.leave()
            settings.stop()
            controller?.stopLoading()
        }
    }

    /// `stop` stops the offline save, the settings watch and the web view.
    private static func leave(model: TopicReaderModel, viewerID: Int, covered: Bool, stop: () -> Void) {
        // Checked again here: `events.left` also comes from the web view leaving its window (issue #750).
        guard model.linkedReader == nil, !covered else { return }
        model.viewDidDisappear(viewer: viewerID)
        stop()
    }

    /// The handlers of the merged lots: "Link", the quotes, "Favoris", "Alerter", "Editer" and "Supprimer". A later lot adds
    /// its handler here, the policy is untouched.
    private func installMenuActions() {
        // Weak: the model stores this registry, a strong capture would keep every reader alive.
        let confirm: @MainActor (String) -> Void = { [weak model] text in
            model?.showMenuFeedback(text) // announced by `ReaderAnnouncements`
        }
        // Weak, declared once out here: a `[weak model]` inside another closure would clash with the outer implicit strong capture.
        let rebuild: @MainActor () -> Void = { [weak model] in model?.applyDisplaySettings() }
        model.quoting = composer?.quoting
        var handlers: [any MessageActionHandler] = [
            LinkActionHandler(copy: { UIPasteboard.general.string = $0.absoluteString }, confirm: confirm)
        ]
        handlers += model.quoteHandlers(confirm: confirm)
        // Capture the binding and the source, not the view: the view holds the model, which stores this registry (a cycle).
        let showProfile = $profile
        let services = self.services
        handlers += authorMenu.handlers(reader: model, composer: composer) { id in
            showProfile.wrappedValue = services.profileModel(memberID: id, listsChanged: rebuild)
        }
        if let flagActions = services.flagActions { handlers.append(FavoriteActionHandler(actions: flagActions, confirm: confirm)) }
        handlers += services.pseudoLists.map {
            PseudoListActionHandler.pair(manager: $0, confirm: confirm, rebuild: rebuild)
        } ?? []
        let openURL = self.openURL
        // Each appearance installs again: a fresh model with the current services, unless an alert is in progress.
        let alerts = self.alerts.flatMap { $0.isIdle ? nil : $0 } ?? ModeratorAlertModel(
            alerter: services.moderatorAlerts, mailAddress: services.moderatorAlertMail, confirm: confirm,
            openMail: { openURL($0) }
        )
        self.alerts = alerts
        handlers.append(alerts.handler)
        if let composer {
            let writes = writes ?? MessageWriteModel(reader: model, services: composer)
            self.writes = writes
            handlers += writes.handlers
        }
        model.install(MessageActionRegistry(handlers))
        controller?.offersSelectionQuote = model.offersSelectionQuote
    }
}

/// The reader a link pushed, identified by its model.
private struct LinkedReader: Hashable {
    let model: TopicReaderModel

    static func == (lhs: LinkedReader, rhs: LinkedReader) -> Bool { lhs.model === rhs.model }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(model)) }
}
