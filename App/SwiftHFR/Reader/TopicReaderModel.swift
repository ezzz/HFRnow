import Foundation
import HFRModels
import HFRParsing
import Observation

// Port of HFRswift/Swift/MessagesView.swift (MessagesView.loadPage, WebView.ScrollRequest) @ 2440d79. Differences: when HFR serves
// another page than the one asked (past the end, R24), the shown target takes the served page number (LOT-167).
/// An HTML document handed to the web view. `token` is unique per model, so an event of an older document is recognised.
struct ReaderDocument: Equatable, Sendable {
    /// Identity of this document; grows with every new document.
    let token: Int
    /// The full page (TopicHTMLBuilder).
    let html: String
    /// Message to scroll to once shown.
    let anchor: Int?
    /// Keep the scroll position of the previous document (a refresh of the same page).
    let keepsScrollPosition: Bool
}

/// A request to scroll the shown document to a message, without reloading it (a link to a post of the same page).
struct ScrollRequest: Equatable, Sendable {
    /// Unique per request, so asking twice for the same message scrolls twice.
    let id: Int
    /// The document the request is for.
    let token: Int
    /// Message number.
    let anchor: Int
}

/// What the reader does with a link the user tapped (LOT-137).
enum ReaderLinkAction: Equatable, Sendable {
    /// A topic or private message page of the forum: opened in the app, at its page and post (`TopicReaderModel.follow`).
    case reader(ReaderTarget)
    /// Anything else on the web, in Safari's view inside the app (`SFSafariViewController`, LOT-071 T8).
    case inAppBrowser(URL)
    /// Anything else on the web, in the system's default browser ("Navigateur par défaut", LOT-119).
    case defaultBrowser(URL)
    /// Not an `http(s)` link: nothing happens.
    case ignored
}

/// State of the topic reader (LOT-083): one page at a time, page navigation, refresh, links.
///
/// Loading rules (LOTS "Issues to open" #6 and #7, issues #107 and #108): one load at a time, a newer load or `cancel()`
/// supersedes the older one, whose result is dropped; the page on screen stays while a load runs and after it fails; a
/// refresh reloads the page on screen. The page the user opens is fetched with the session exactly once (E25); nothing
/// is prefetched.
@MainActor
@Observable
final class TopicReaderModel {
    /// The page shown, nil before the first successful load.
    private(set) var page: ReaderPage?
    /// A load is running.
    private(set) var isLoading = false
    /// Failure of the latest load; cleared by the next success.
    private(set) var error: ListLoadError?
    /// The document for the web view; replaced by every successful load.
    private(set) var document: ReaderDocument?
    /// The token of the last document the web view reported as ready (DOMContentLoaded and images routed).
    private(set) var readyToken: Int?
    /// Latest in-page scroll request.
    private(set) var scrollRequest: ScrollRequest?
    /// The reader a followed link opened, shown above this one; going back clears it and finds this page as it was left
    /// (LOT-137, legacy pushes a reader per link: `MessagesView.swift:3896-3927` at `21173e77`).
    private(set) var linkedReader: TopicReaderModel?
    /// HFR's confirmation of the reply just sent, shown until dismissed; set only by a confirmed reply (LOT-084).
    private(set) var replyConfirmation: String?
    /// Title until the page gives its own.
    let initialTitle: String

    /// The page last asked for (shown, or failed): what "Réessayer" asks again.
    private(set) var requested: ReaderTarget
    /// Where the page last asked for opens, kept so "Réessayer" after a failed latest-post load still opens at the end.
    private var requestedAnchor: AnchorRule
    /// The page last asked for is a conversation's latest page whose pager is followed (LOT-128), kept for "Réessayer".
    private var requestedFollowsPager = false
    /// The target of the page on screen (topic and page as served), what a refresh reloads.
    private(set) var shown: ReaderTarget?

    private let source: any TopicPageSource
    private let renderOptions: @Sendable () -> ReaderRenderOptions
    /// The options the document on screen was built with, to spot a setting that changed since.
    private var appliedOptions: ReaderRenderOptions?
    private var generation = 0
    private var nextToken = 0
    private var nextScrollID = 0
    private var task: Task<Void, Never>?

    /// A reader that will open `target`; nothing is fetched before `onAppear()`. With `opensAtLastMessage` the first load
    /// (and "Réessayer" after its failure) opens at the page's last message like a reply does, for a link that stands for
    /// "the latest message" (legacy `#bas`) rather than for a message of its own.
    init(
        target: ReaderTarget,
        title: String = "",
        source: any TopicPageSource,
        opensAtLastMessage: Bool = false,
        renderOptions: @escaping @Sendable () -> ReaderRenderOptions = { ReaderRenderOptions() }
    ) {
        self.requested = target
        self.requestedAnchor = opensAtLastMessage ? .lastMessage : .target
        self.initialTitle = title
        self.source = source
        self.renderOptions = renderOptions
    }

    /// Navigation title.
    var title: String {
        if let title = page?.title, !title.isEmpty { return title }
        return initialTitle
    }

    /// The web view has shown a document at least once (the first page appears at DOMContentLoaded, not blank before).
    var hasShownDocument: Bool { readyToken != nil }

    /// First appearance: loads the target once. A view that appears again (rotation, column change) loads nothing.
    func onAppear() async {
        guard page == nil, !isLoading, error == nil else { return }
        await load(requested, keepsScrollPosition: false, anchor: requestedAnchor)
    }

    /// Reloads the page on screen (not page 1, not the page first opened); the content stays while it runs and after a
    /// failure. Before anything is shown, retries the first load.
    func refresh() async {
        guard let shown else {
            await load(requested, keepsScrollPosition: false, anchor: requestedAnchor)
            return
        }
        await load(ReaderTarget(source: shown.source, page: shown.page), keepsScrollPosition: true)
    }

    /// Asks again for the page that failed; a conversation's latest page still follows its pager (`showLatestPost`).
    func retry() async {
        if requestedFollowsPager {
            await loadLatestPage(requested)
        } else {
            await load(requested, keepsScrollPosition: false, anchor: requestedAnchor)
        }
    }

    /// Opens page `number` of the topic (clamped to the known pages).
    func goToPage(_ number: Int) async {
        guard let shown, let page else { return }
        let clamped = min(max(1, number), page.maxPage)
        await load(shown.atPage(clamped), keepsScrollPosition: false)
    }

    /// Rebuilds the page on screen when a display setting (layout, signatures) changed since it was built, without a
    /// request: the typed page is kept, so only the document changes and the scroll position stays. A no-op when nothing
    /// changed or nothing is shown, so it is cheap to call on every settings notification.
    func applyDisplaySettings() {
        guard let page, let appliedOptions, !isLoading else { return }
        let options = renderOptions()
        guard options != appliedOptions else { return }
        self.appliedOptions = options
        nextToken += 1
        document = ReaderDocument(
            token: nextToken,
            html: TopicHTMLBuilder.document(for: page, token: nextToken, options: options),
            anchor: nil,
            keepsScrollPosition: true
        )
    }

    /// Follows a page swipe (legacy `DragGesture`): the next page opens at its top, the previous one at its last message.
    func swipe(_ swipe: PageSwipe) async {
        guard let shown, let page, !isLoading else { return }
        switch swipe {
        case .next where page.currentPage < page.maxPage:
            await load(shown.atPage(page.currentPage + 1), keepsScrollPosition: false)
        case .previous where page.currentPage > 1:
            await load(shown.atPage(page.currentPage - 1), keepsScrollPosition: false, anchor: .lastMessage)
        default: break
        }
    }

    /// Whether a previous page exists.
    var canGoToPrevious: Bool { (page?.currentPage ?? 1) > 1 }
    /// Whether a next page exists.
    var canGoToNext: Bool { page.map { $0.currentPage < $0.maxPage } ?? false }

    /// Follows a forum link: a post of the page shown is scrolled to without a request; anything else opens in a new reader
    /// above this one (`linkedReader`), so going back returns to this page at the position it was left.
    func follow(_ target: ReaderTarget) {
        // A second tap while the pushed reader is on its way: the first link wins.
        guard linkedReader == nil else { return }
        // A message link names no page (issue #106): it is on screen when the page shown holds that message.
        if let shown, let page, let anchor = target.anchor, target.source == shown.source,
           target.numreponse != nil || target.page == page.currentPage,
           let document, page.messages.contains(where: { !$0.isContinuation && $0.numreponse == anchor }) {
            nextScrollID += 1
            scrollRequest = ScrollRequest(id: nextScrollID, token: document.token, anchor: anchor)
            return
        }
        linkedReader = TopicReaderModel(
            target: target, title: target.source == shown?.source ? title : "", source: source, renderOptions: renderOptions
        )
    }

    /// Whether this reader shows a private conversation (`cat=prive`).
    var isPrivateConversation: Bool {
        switch requested.source {
        case .topic(let topic): topic.category == .privateMessages
        }
    }

    /// The reader opened by a link was closed (back).
    func closeLinkedReader() {
        linkedReader = nil
    }

    /// What the reply composer needs from the page on screen; nil when the page offers no answer form (logged out, locked
    /// topic: `#repondre_form` is absent, LOT-033), names no topic (the draft is kept per topic), or its answer link names
    /// another topic.
    var replyTarget: ReplyTarget? {
        // Same origin rule as `PostingFlow`: a link it would refuse (another port) offers no reply.
        guard let page, let formURL = page.answerURL, formURL.port == nil || formURL.port == 443,
              let topic = page.topicID else { return nil }
        // `#repondre_form` comes after the messages (`R61d`) and its link carries `cat` and `post`: a link that names
        // another topic would post there under this topic's draft, so a parser slip offers no reply instead.
        guard HFRURL.topicID(in: formURL.absoluteString) == topic else { return nil }
        return ReplyTarget(formURL: formURL, topic: topic)
    }

    /// The reply sheet closed: after a confirmed reply, shows HFR's sentence and the topic's latest post; after an
    /// unconfirmed one, the latest post only, so the user sees whether it was posted. Closing with or without the draft
    /// changes nothing.
    func composerDidClose(_ reason: ReplyComposerModel.CloseReason) async {
        switch reason {
        case .sent(let result):
            replyConfirmation = result.message
            await showLatestPost()
        case .checkTopic:
            await showLatestPost()
        case .keptDraft, .discardedDraft, .closedWithoutSaving:
            break
        }
    }

    /// Hides the reply confirmation.
    func clearReplyConfirmation() {
        replyConfirmation = nil
    }

    /// After a reply: opens the topic's last page at its last message, where HFR appends a reply (`R61d`). The page after
    /// the last known one is asked for, since the reply may have opened it; past the end HFR redirects to the last page (`R24`,
    /// on `forum2.php` and on the canonical path alike).
    /// HFR's own refresh is not used: after a form fetched at `page=1` it names page 1 (`W30`: `…_1.htm#bas`), and whether
    /// it echoes another form `page` after a reply is not captured.
    ///
    /// A private thread (LOT-128) never asks past its end: what HFR serves for a page after the last one of a `cat=prive`
    /// thread is not captured (`R24` is a public topic). Its last known page is asked for; when that page's pager says
    /// the reply opened a new one, that page is asked for next.
    func showLatestPost() async {
        guard let page, let shown else { return }
        guard page.topicID?.category == .privateMessages else {
            await load(shown.atPage(page.maxPage + 1), keepsScrollPosition: false, anchor: .lastMessage)
            return
        }
        await loadLatestPage(shown.atPage(page.maxPage))
    }

    /// Loads `target` at its last message, then the page its pager names when it is later (a reply opened it). "Réessayer"
    /// after a failure comes back here, so the follow-up is not lost.
    private func loadLatestPage(_ target: ReaderTarget) async {
        let delivered = await load(target, keepsScrollPosition: false, anchor: .lastMessage, followsPager: true)
        // Only when that load delivered (not superseded, no failure) and its pager names a later page.
        guard delivered, error == nil, let served = page, let servedTarget = shown,
              served.maxPage > served.currentPage else { return }
        await load(servedTarget.atPage(served.maxPage), keepsScrollPosition: false, anchor: .lastMessage)
    }

    /// Stops the load in flight; the content stays.
    func cancel() {
        let interrupted = task != nil
        task?.cancel()
        task = nil
        generation += 1
        isLoading = false
        if interrupted { applyDisplaySettings() } // a setting changed during the load that never delivered
    }

    /// The web view reports a document as ready; an older document's report is ignored.
    func documentDidBecomeReady(token: Int) {
        guard token == document?.token else { return }
        readyToken = token
    }

    /// What tapping `url` does. Topic and private message links of the forum, as LOT-095's router reads them, open in the
    /// app at their page and post (issue #106); other web links open in the browser `defaultBrowser` names (legacy
    /// `MessagesView.swift:3963-3968` at `21173e77`). A forum page the router sends elsewhere (a list, a profile, a page
    /// view it does not own) opens in the browser too, never in the reader with the session.
    func action(forLink url: URL, defaultBrowser: Bool) -> ReaderLinkAction {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return .ignored }
        if let target = ReaderTarget(link: url.absoluteString) { return .reader(target) }
        return defaultBrowser ? .defaultBrowser(url) : .inAppBrowser(url)
    }

    /// The video `index` of message `post` on the page shown, for the player opened on tap (D-071-2).
    func video(post: Int, index: Int, token: Int) -> MessageEmbed? {
        guard token == document?.token, let message = page?.messages.first(where: { $0.numreponse == post }),
              message.content.embeds.indices.contains(index) else { return nil }
        return message.content.embeds[index]
    }

    // MARK: - Loading

    /// Where a loaded document opens.
    private enum AnchorRule {
        /// At the target's own anchor, when the page holds it.
        case target
        /// At the page's last message (after a reply).
        case lastMessage
    }

    /// Returns whether this load delivered its result (false when a newer load or `cancel()` superseded it).
    @discardableResult
    private func load(
        _ target: ReaderTarget, keepsScrollPosition: Bool, anchor rule: AnchorRule = .target, followsPager: Bool = false
    ) async -> Bool {
        task?.cancel()
        generation += 1
        let mine = generation
        requested = target
        requestedAnchor = rule
        requestedFollowsPager = followsPager
        isLoading = true
        let source = self.source
        let task = Task { [weak self] in
            let result: Result<ReaderPage, ListLoadError>
            do throws(ListLoadError) {
                result = .success(try await source.page(for: target))
            } catch {
                result = .failure(error)
            }
            self?.finish(result, target: target, keepsScrollPosition: keepsScrollPosition, anchor: rule, generation: mine)
        }
        self.task = task
        await task.value
        return generation == mine
    }

    private func finish(
        _ result: Result<ReaderPage, ListLoadError>, target: ReaderTarget, keepsScrollPosition: Bool, anchor rule: AnchorRule,
        generation mine: Int
    ) {
        // A superseded or cancelled load never delivers (issue #108).
        guard mine == generation else { return }
        isLoading = false
        task = nil
        switch result {
        case .success(let loaded):
            let source = loaded.topicID.map(ReaderTarget.Source.topic) ?? target.source
            // HFR may serve another page than the one asked (past the end): the target follows the page served.
            shown = ReaderTarget(source: source).atPage(loaded.currentPage)
            page = loaded
            error = nil
            nextToken += 1
            let anchor: Int? = switch rule {
            case .target:
                target.anchor.flatMap { anchor in
                    loaded.messages.contains { !$0.isContinuation && $0.numreponse == anchor } ? anchor : nil
                }
            case .lastMessage:
                loaded.messages.last { !$0.isContinuation }?.numreponse
            }
            let options = renderOptions()
            appliedOptions = options
            document = ReaderDocument(
                token: nextToken,
                html: TopicHTMLBuilder.document(for: loaded, token: nextToken, options: options),
                anchor: anchor,
                keepsScrollPosition: keepsScrollPosition && anchor == nil
            )
        case .failure(.cancelled):
            break
        case .failure(let failure):
            error = failure
        }
        applyDisplaySettings() // a setting changed while this load ran and did not deliver a page
    }
}
