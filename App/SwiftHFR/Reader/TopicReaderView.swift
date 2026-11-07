import HFRModels
import SafariServices
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
    /// The offline save of this topic (LOT-139); nil without offline services (the offline reader, previews).
    @State private var saver: OfflineSaveModel?
    @State private var external: ExternalLink?
    @State private var video: VideoItem?
    /// The open image viewer (LOT-109); a fresh model per tap.
    @State private var viewer: ImageViewerModel?
    @State private var profile: UserProfileModel?
    @State private var askingPage = false
    @State private var pageText = ""
    /// `topic_page_swipe_navigation`: with it off no gesture is attached to the web view, as legacy's `including: .none`.
    @State private var swipeEnabled = true
    /// "Editer" and "Supprimer" of the message menu (LOT-088); nil until the menu is installed, and logged out.
    @State private var writes: MessageWriteModel?
    /// `reply_button_behavior` (LOT-086), read again with the other settings.
    @State private var replyBehavior = ReplyButtonBehavior.quick
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.isSelectedRootTab) private var isSelectedTab

    var body: some View {
        ZStack {
            if let controller {
                // The page runs under the bars and banners (HIG Layout: extend content under the bars, LOT-186); what they cover
                // is the safe area this full-height reader ignores, handed to the web view.
                GeometryReader { proxy in
                    ReaderWebView(
                        controller: controller, document: model.document, scrollRequest: model.scrollRequest,
                        obscured: proxy.safeAreaInsets
                    )
                }
                .ignoresSafeArea(edges: .vertical)
                .opacity(model.hasShownDocument ? 1 : 0)
                .accessibilityHidden(!model.hasShownDocument)
                .simultaneousGesture(pageSwipe, including: swipeEnabled ? .all : .none)
            }
            overlay
        }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(ReaderTabBar.visibility(sizeClass: sizeClass, isSelectedTab: isSelectedTab), for: .tabBar)
        .safeAreaInset(edge: .top) {
            if let error = model.error, model.page != nil {
                LoadFailureBanner(error: error, retry: model.retry)
            }
        }
        .modifier(ReaderReplyFlow(model: model, composer: composer))
        .modifier(ReaderEditFlow(writes: writes))
        .modifier(ReaderSearchFlow(model: model, composer: composer))
        .modifier(ReaderPollFlow(model: model, composer: composer))
        .modifier(ReaderMarkUnreadFlow(model: model, actions: services.flagActions, host: onMarkUnread))
        .offlineSave(model: model, saver: saver)
        .toolbar {
            ReaderPageControls(model: model, askPage: askForPage, replySymbol: replySymbol)
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await model.refresh() } } label: { Label("Actualiser", systemImage: "arrow.clockwise") }
                    .disabled(model.isLoading)
            }
            if let onFilterPosts {
                ToolbarItem(placement: .secondaryAction) {
                    Button(action: onFilterPosts) {
                        Label("Filtrer les posts", systemImage: "line.3.horizontal.decrease")
                    }
                    .disabled(filterIsBusy)
                }
            }
            // The system "…" overflow: legacy `pageChoiceMenuItems` after the other actions, only past one page (#582).
            if let page = model.page, page.maxPage > 1 {
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
        .confirmationDialog(
            "Actions du message", isPresented: Binding(get: { model.presentedMenu != nil }, set: { if !$0 { model.dismissMenu() } }),
            titleVisibility: .hidden, presenting: model.presentedMenu
        ) { menu in
            ForEach(menu.entries, id: \.kind) { action in
                Button(role: action.isDestructive ? .destructive : nil) {
                    Task { await model.perform(action, in: menu) }
                } label: { Label(action.title, systemImage: action.systemImageName) }
            }
            Button("Annuler", role: .cancel) {}
        }
        .overlay(alignment: .bottom) { menuFeedbackBanner }
        .sheet(item: $external) { link in SafariView(url: link.url).ignoresSafeArea() }
        .sheet(item: $video) { item in VideoPlayerSheet(embed: item.embed) }
        .fullScreenCover(item: $viewer) { ImageViewerView(model: $0) }
        .sheet(item: $profile) { profile in UserProfileView(model: profile, services: services) }
        .navigationDestination(item: linkedReader) { linked in
            // A private conversation reached from a topic offers no reply: MP replies are LOT-128's (no composer in Messages).
            TopicReaderView(model: linked.model, services: services, composer: linked.model.isPrivateConversation ? nil : composer)
        }
        .onAppear(perform: makeController)
        .onAppear {
            if saver == nil, let offline = services.offline { saver = OfflineSaveModel(store: offline.store, fetcher: offline.fetcher) }
        }
        // The selection menu offers its quotes once the page has an answer form (and not at all logged out).
        .onChange(of: model.canQuote) { _, canQuote in controller?.offersSelectionQuote = canQuote }
        .task {
            // The settings screen writes `UserDefaults`: a display setting changed there reaches the open reader at once.
            swipeEnabled = services.settings.swipesPages()
            replyBehavior = services.settings.replyButton()
            model.applyDisplaySettings() // a change made while this reader was away
            for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                swipeEnabled = services.settings.swipesPages()
                replyBehavior = services.settings.replyButton()
                model.applyDisplaySettings()
            }
        }
        .task {
            installMenuActions()
            await model.onAppear()
        }
        .onDisappear {
            // Covered by the reader of a followed link: this page stays as it is, for the way back.
            // Same for the image viewer (a full-screen cover calls it): stopping would turn the pending pictures into links.
            guard model.linkedReader == nil, viewer == nil else { return }
            model.cancel()
            saver?.leave()
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
        guard composer != nil, model.replyTarget != nil, replyBehavior != .hidden else { return nil }
        return replyBehavior == .forum ? "square.and.pencil" : "plus"
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

    /// The handlers of the merged lots: "Link", the quotes, "Favoris", "Editer" and "Supprimer". A later lot adds its handler
    /// here, the policy is untouched.
    private func installMenuActions() {
        // Weak: the model stores this registry, a strong capture would keep every reader alive.
        let confirm: @MainActor (String) -> Void = { [weak model] text in
            model?.showMenuFeedback(text)
            AccessibilityNotification.Announcement(text).post()
        }
        model.quoting = composer?.quoting
        var handlers: [any MessageActionHandler] = [
            LinkActionHandler(copy: { UIPasteboard.general.string = $0.absoluteString }, confirm: confirm)
        ]
        handlers += model.quoteHandlers(confirm: confirm)
        if let flagActions = services.flagActions { handlers.append(FavoriteActionHandler(actions: flagActions, confirm: confirm)) }
        if let composer {
            let writes = writes ?? MessageWriteModel(reader: model, services: composer)
            self.writes = writes
            handlers += writes.handlers
        }
        model.install(MessageActionRegistry(handlers))
        controller?.offersSelectionQuote = model.canQuote
    }

    private func makeController() {
        guard controller == nil else { return }
        let controller = ReaderWebController(
            imageFetcher: services.imageFetcher, autoLoadsThirdPartyImages: services.settings.autoLoadsThirdPartyImages
        )
        controller.events = ReaderWebController.Events(
            ready: { [model] token in model.documentDidBecomeReady(token: token) },
            link: { [model] url in
                switch model.action(forLink: url, defaultBrowser: services.settings.opensLinksInDefaultBrowser()) {
                case .reader(let target): model.follow(target)
                case .profile(let memberID): profile = UserProfileModel(memberID: memberID, source: services.profiles)
                case .inAppBrowser(let url): external = ExternalLink(url: url)
                case .defaultBrowser(let url): openURL(url)
                case .ignored: break
                }
            },
            video: { [model] post, index, token in
                if let embed = model.video(post: post, index: index, token: token) { video = VideoItem(embed: embed) }
            },
            position: { [model] post, token in Task { await model.recordPosition(post: post, token: token) } },
            menu: { [model] post, source, token in Task { await model.openMenu(post: post, source: source, token: token) } },
            quote: { [model] post, text, bold, token in
                Task { await model.quoteSelection(post: post, text: text, bold: bold, token: token) }
            },
            image: { images, index, _ in
                // The controller already checked the document token (a stale page's tap never gets here).
                viewer = ImageViewerModel(images: images, index: index, services: .live(fetcher: services.imageFetcher))
            }
        )
        model.positions = services.positions
        controller.offersSelectionQuote = model.canQuote
        self.controller = controller
    }
}

/// What the reader shares across pages: the image client, the settings it reads and the position recorder.
struct ReaderServices: Sendable {
    /// Images through the cookie-less client.
    let imageFetcher: ReaderImageFetcher
    /// Image mode and display choices.
    let settings: ReaderSettings
    /// Public profiles opened from a link (LOT-116), fetched without cookies.
    let profiles: any UserProfileSource
    /// Records the reading position of the current account (LOT-111); nil when logged out.
    var positions: (any ReaderPositionRecording)?
    /// Offline reading (LOT-139): saving the open topic and the list of saved ones; nil in the offline reader itself.
    var offline: OfflineServices?
    /// Flag writes of the current account, for "Favoris" (LOT-125) and "Marquer comme non lu" (LOT-127); nil when logged out.
    var flagActions: TopicFlagActions?
}

/// Hosts the controller's web view and hands it the model's document, scroll requests and what the bars cover of it.
struct ReaderWebView: UIViewRepresentable {
    let controller: ReaderWebController
    let document: ReaderDocument?
    let scrollRequest: ScrollRequest?
    /// The bars and banners over the page (top and bottom only: the page keeps the horizontal safe area).
    var obscured = EdgeInsets()

    func makeUIView(context: Context) -> WKWebView { controller.webView }

    func updateUIView(_ webView: WKWebView, context: Context) {
        controller.textScale = context.environment.textScale
        controller.theme = context.environment.themeAppearance
        controller.obscuredInsets = UIEdgeInsets(top: obscured.top, left: 0, bottom: obscured.bottom, right: 0)
        controller.show(document)
        controller.apply(scrollRequest)
    }
}

/// The reader a link pushed, identified by its model.
private struct LinkedReader: Hashable {
    let model: TopicReaderModel

    static func == (lhs: LinkedReader, rhs: LinkedReader) -> Bool { lhs.model === rhs.model }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(model)) }
}

struct ExternalLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct VideoItem: Identifiable {
    let embed: MessageEmbed
    var id: String { embed.embedURL.absoluteString }
}

/// A web link opened outside the reader, in Safari's own view (LOT-071 T8): Safari's data, not the app's. Legacy
/// `SafariInAppView` (`MessagesView.swift:2874-2885` at `21173e77`).
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
