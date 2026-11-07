import Foundation
import HFRModels
import HFRParsing
import Observation

// Port of HFRswift/Swift/MessagesView.swift (MessagesView.loadPage, WebView.ScrollRequest) @ 2440d79. Differences: when HFR serves
// another page than the one asked (past the end, R24), the shown target takes the served page number (LOT-167);
// the reading position is recorded per account and the flag message is followed by the legacy separator (LOT-111, GAP-063, UXD-11).
/// State of the topic reader (LOT-083): one page at a time, page navigation, refresh, links.
///
/// Loading rules (LOTS "Issues to open" #6 and #7, issues #107 and #108): one load at a time, a newer load or `cancel()`
/// supersedes the older one, whose result is dropped; the page on screen stays while a load runs and after it fails; a
/// refresh reloads the page on screen. The page the user opens is fetched with the session exactly once (E25); nothing
/// is prefetched.
@MainActor
@Observable
// The reader's state is one class (LOT-083); LOT-086 adds the quote request to it. Splitting it is a refactor of its own.
// swiftlint:disable:next type_body_length
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
    /// HFR's confirmation of the reply, edit or delete just sent, shown until dismissed; set only by a confirmed write (LOT-084,
    /// LOT-088).
    private(set) var replyConfirmation: String?
    /// The message menu on screen; nil when none.
    var presentedMenu: MessageMenu?
    /// Short confirmation of the last menu action ("Lien copié"), shown until cleared.
    var menuFeedback: String?
    /// Grows with every confirmation, so the view restarts its timer when the same text comes twice.
    var menuFeedbackSerial = 0
    /// The reply the reader asks its screen to open: set by "Répondre" and by a quote, taken by `takePendingReply()` (LOT-086).
    var pendingReply: ReplyRequest?
    /// A quote is being fetched: another one waits for it, as legacy's `isLoadingQuoteTemplate` (LOT-086).
    var isLoadingQuote = false
    /// The messages of this topic selected for a multi-quote, as last read from the session (the menu reads it again before it opens).
    var quoteSelected: Set<Int> = []
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

    /// Where reading positions go (LOT-111); nil when logged out or in a preview.
    @ObservationIgnored var positions: (any ReaderPositionRecording)?

    /// The poll sheet's model, kept here (not in a view) so it outlives the view: a vote in flight or possibly counted is
    /// never offered again from a fresh form when the topic is reopened (LOT-136).
    private var heldPoll: PollModel?

    private let source: any TopicPageSource
    var registry = MessageActionRegistry()
    /// The multi-quote selection and the quote engine of the current account; nil when logged out (LOT-086).
    @ObservationIgnored var quoting: (any QuoteOpening)?
    let renderOptions: @Sendable () -> ReaderRenderOptions
    /// The options the document on screen was built with, to spot a setting that changed since.
    private var appliedOptions: ReaderRenderOptions?
    /// The flag message the document draws a line after (legacy separator, LOT-111).
    private var separatorAfter: Int?
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
        let options = currentRenderOptions()
        guard options != appliedOptions else { return }
        self.appliedOptions = options
        nextToken += 1
        document = ReaderDocument(
            token: nextToken,
            html: TopicHTMLBuilder.document(for: page, token: nextToken, options: options, separatorAfter: separatorAfter),
            anchor: nil,
            keepsScrollPosition: true
        )
    }

    /// Follows a page swipe (legacy `DragGesture`): the next page opens at its top, the previous one at its last message.
    func swipe(_ swipe: PageSwipe) async {
        // Not while the web view still shows the previous document: the page on screen would be the wrong starting point.
        guard let shown, let page, !isLoading, readyToken == document?.token else { return }
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

    /// The model of the page's poll for the sheet; nil when the page has none. The held model is reused for this account
    /// while it holds a vote (sending, counted or possibly counted); otherwise a fresh one starts from the page's poll.
    func pollModel(voter: (any PollVoting)?, account: String?) -> PollModel? {
        guard let poll = page?.poll else { return nil }
        if let held = heldPoll, held.account == account, held.holdsVote {
            held.pageDidReload(poll)
            return held
        }
        let fresh = PollModel(poll: poll, voter: voter, account: account, reload: { [weak self] in await self?.refresh() })
        heldPoll = fresh
        return fresh
    }

    /// Hides the reply confirmation.
    func clearReplyConfirmation() {
        replyConfirmation = nil
    }

    /// Shows HFR's sentence for a confirmed write on a message of this page (LOT-088).
    func showConfirmation(_ sentence: String) {
        replyConfirmation = sentence
    }

    /// Reloads the page on screen after an edit or a delete: at message `post` (the first one after it when it went) without
    /// the separator a followed anchor draws, or where the user was when `post` is nil. HFR's own refresh names the form's
    /// `page`, this very page (`W31`, `W32`), and past the end it redirects to the last page (`R24`).
    func reloadPage(at post: Int?) async {
        guard let shown else { return }
        await load(shown.atPage(shown.page), keepsScrollPosition: post == nil, anchor: post.map(AnchorRule.message) ?? .target)
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
    /// view it does not own) opens in the browser too, never in the reader with the session; a profile opens the profile
    /// sheet (LOT-116), which fetches it without cookies.
    func action(forLink url: URL, defaultBrowser: Bool) -> ReaderLinkAction {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return .ignored }
        if let target = ReaderTarget(link: url.absoluteString) { return .reader(target) }
        if case .profile(let memberID) = HFRLinkRoute.route(for: url) { return .profile(memberID: memberID) }
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
    private enum AnchorRule: Equatable {
        /// At the target's own anchor, when the page holds it.
        case target
        /// At the page's last message (after a reply).
        case lastMessage
        /// At this message, or the first one after it (after an edit).
        case message(Int)
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
            heldPoll?.pageDidReload(loaded.poll)
            error = nil
            nextToken += 1
            presentedMenu = nil
            let anchor: Int? = switch rule {
            case .target:
                // The flag message, or the first one after it when it was deleted (legacy `closePostID`, LOT-111).
                target.anchor.flatMap { anchor in
                    loaded.messages.first { !$0.isContinuation && $0.numreponse >= anchor }?.numreponse
                }
            case .lastMessage:
                loaded.messages.last { !$0.isContinuation }?.numreponse
            case .message(let post):
                loaded.messages.first { !$0.isContinuation && $0.numreponse >= post }?.numreponse
            }
            let options = currentRenderOptions()
            appliedOptions = options
            separatorAfter = rule == .target ? target.anchor : nil
            document = ReaderDocument(
                token: nextToken,
                html: TopicHTMLBuilder.document(for: loaded, token: nextToken, options: options, separatorAfter: separatorAfter),
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
