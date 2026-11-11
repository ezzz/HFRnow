import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
import Observation

// One class holds the reader's state (below); its loading rules (#108, #566) stay next to the state they guard.
// swiftlint:disable file_length

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
    /// Where "Marquer comme non lu" stands (LOT-127).
    var markUnreadState = MarkUnreadState.idle
    /// The reply the reader asks its screen to open: set by "Répondre" and by a quote, taken by `takePendingReply()` (LOT-086).
    var pendingReply: ReplyRequest?
    /// A quote is being fetched: another one waits for it, as legacy's `isLoadingQuoteTemplate` (LOT-086).
    var isLoadingQuote = false
    /// The messages of this topic selected for a multi-quote, as last read from the session (the menu reads it again before it opens).
    var quoteSelected: Set<Int> = []
    /// Title until the page gives its own.
    let initialTitle: String
    /// The composers open over this reader (#653): while one is, the page still scrolls but its taps and actions do nothing.
    private(set) var openComposers: Set<ReaderComposer> = []

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
    /// Places the legacy reply draft the import left for this topic when a page of it is delivered (LOT-158); nil when logged
    /// out or in a preview.
    @ObservationIgnored var legacyDrafts: LegacyDraftResolver?
    /// The last placement started by a delivered page (tests await it).
    @ObservationIgnored private(set) var legacyDraftTask: Task<Void, Never>?

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
    /// The reader view instance that appeared last (`ReaderViewerID`): only its disappearance stops a load. Two views can
    /// share this model (a replacement view appears before the old one disappears), and the old one must not stop the load
    /// the new one waits for (issue #566).
    private var viewer: Int?
    /// The document `documentDidFail` reported: its error ends when that same document reports ready, never another one's.
    private var failedToken: Int?
    private var nextToken = 0
    private var nextScrollID = 0
    private var task: Task<Void, Never>?
    /// The viewer on screen when the web view reported `readyToken`: another view has its own web view, which has not shown
    /// that document yet (issue #750).
    private var readyViewer: Int?

    /// The longest the reader shows "Chargement des messages" before it offers "Réessayer" (issue #750): HFRNetwork's limit for
    /// a topic page request (`RequestTimeout.standard`, legacy `kTimeoutMini`), so a wait no request can end turns into an
    /// error after the time a request itself may take. Legacy's own 10 s (`HFRNetworkTimeout.content`, `MessagesView.swift:
    /// 3684-3693` @ 87fe0d1c) covers the fetch only, not the web view, where most of a first open goes (#750 measurement).
    nonisolated static let waitLimit = Duration.seconds(RequestTimeout.standard)
    /// How the wait is timed; tests replace it with a clock they drive.
    @ObservationIgnored var waitClock: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    @ObservationIgnored private var waitWatch: Task<Void, Never>?
    /// The current wait ended on `waitLimit`: the screen coming back loads again, as it does after a stopped load.
    private var waitExpired = false

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

    /// First appearance: loads the target once. A view that appears again (rotation, column change) loads nothing, unless
    /// nothing is shown, loading or failed (a load stopped when a view went away): then it loads again. `viewer` names the
    /// view that appears, which becomes the one whose disappearance may stop a load (`viewDidDisappear`).
    func onAppear(viewer: Int? = nil) async {
        // A `.task` whose view already went away (a quick tab flick) must not take the load over from the view still there.
        guard !Task.isCancelled else { return }
        if let viewer {
            self.viewer = viewer
            // A new view (the same topic opened again) has a new web view: the document is not shown until it says so (#750).
            if readyToken != nil, let shownBy = readyViewer, shownBy != viewer { readyToken = nil }
        }
        ReaderLog.debug(
            "appear model=\(debugID) viewer=\(viewer ?? -1) page=\(page != nil) loading=\(isLoading) error=\(error != nil)"
        )
        watchWait()
        guard page == nil, !isLoading, error == nil || waitExpired else { return }
        await load(requested, keepsScrollPosition: false, anchor: requestedAnchor)
    }

    /// A reader view went away: stops the load in flight only when that view is the last one that appeared, so a view
    /// replaced by another one on the same model never stops the new view's load (issue #566).
    func viewDidDisappear(viewer: Int) {
        let current = self.viewer == viewer
        ReaderLog.debug("disappear model=\(debugID) viewer=\(viewer) current=\(current) loading=\(isLoading)")
        guard current else { return }
        self.viewer = nil
        cancel()
    }

    /// A number for the debug trace that tells models apart; never shown.
    private var debugID: Int { ObjectIdentifier(self).hashValue & 0xFFFF }

    /// Reloads the page on screen (not page 1, not the page first opened); the content stays while it runs and after a
    /// failure. Before anything is shown, retries the first load.
    func refresh() async {
        guard !suspendsPageInteractions else { return }
        guard let shown else {
            await load(requested, keepsScrollPosition: false, anchor: requestedAnchor)
            return
        }
        await load(ReaderTarget(source: shown.source, page: shown.page), keepsScrollPosition: true)
    }

    /// Asks again for the page that failed; a conversation's latest page still follows its pager (`showLatestPost`).
    func retry() async {
        guard !suspendsPageInteractions else { return }
        if requestedFollowsPager {
            await loadLatestPage(requested)
        } else {
            await load(requested, keepsScrollPosition: false, anchor: requestedAnchor)
        }
    }

    /// Opens page `number` of the topic (clamped to the known pages), at its top or, `atLastMessage`, at its last message
    /// (legacy ‹ and "Dernier post", `MessagesView.swift:4168-4178, 4234-4236` @ 2440d79).
    func goToPage(_ number: Int, atLastMessage: Bool = false) async {
        guard !suspendsPageInteractions, let shown, let page else { return }
        let clamped = min(max(1, number), page.maxPage)
        await load(shown.atPage(clamped), keepsScrollPosition: false, anchor: atLastMessage ? .lastMessage : .target)
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

    /// `applyDisplaySettings()` as a hook that holds this model weakly, for a sheet that outlives the tap that opened it.
    var displaySettingsHook: @MainActor () -> Void { { [weak self] in self?.applyDisplaySettings() } }

    /// Follows a page swipe (legacy `DragGesture`): the next page opens at its top, the previous one at its last message.
    func swipe(_ swipe: PageSwipe) async {
        // Not while the web view still shows the previous document: the page on screen would be the wrong starting point.
        guard !suspendsPageInteractions, let shown, let page, !isLoading, readyToken == document?.token else { return }
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
        guard !suspendsPageInteractions, linkedReader == nil else { return }
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

    /// A composer over this reader opened or closed (#653): its presenter reports it, from the sheet's own state.
    func composer(_ composer: ReaderComposer, isOpen: Bool) {
        if isOpen { openComposers.insert(composer) } else { openComposers.remove(composer) }
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

    /// The model of the page's poll for the sheet; nil when the page has none or a composer is open over it (#653). The held
    /// model is reused for this account while it holds a vote (sending, counted or possibly counted); otherwise a fresh one
    /// starts from the page's poll.
    func pollModel(voter: (any PollVoting)?, account: String?) -> PollModel? {
        guard offersPoll, let poll = page?.poll else { return nil }
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
        if interrupted { ReaderLog.debug("load cancelled model=\(debugID) generation=\(generation)") }
        task?.cancel()
        task = nil
        generation += 1
        isLoading = false
        if interrupted { applyDisplaySettings() } // a setting changed during the load that never delivered
        watchWait()
    }

    /// The web view reports a document as ready; an older document's report is ignored.
    func documentDidBecomeReady(token: Int) {
        guard token == document?.token else { return }
        readyToken = token
        readyViewer = viewer
        // The same document shown after all (loaded again when its screen came back): its own failure is over.
        if failedToken == token {
            failedToken = nil
            error = nil
        }
        watchWait()
    }

    /// The web view could not show the document `token` (its navigation failed twice): the screen offers a retry instead of
    /// waiting (issue #566). An older document's report is ignored. The controller reports only a navigation of its own that
    /// never became ready, so an earlier ready of the same token (another view's web view) does not hide this failure.
    func documentDidFail(token: Int) {
        guard token == document?.token else { return }
        ReaderLog.debug("document failed model=\(debugID) token=\(token)")
        failedToken = token
        readyToken = nil
        error = .other
        watchWait()
    }

    /// Bounds the wait on "Chargement des messages" (issue #750): one watch per wait, from the moment the screen starts
    /// waiting (no page yet, or a page whose document the web view has not shown) until it stops; on `waitLimit` the wait
    /// turns into `timedOut` with "Réessayer". A document that becomes ready after all still shows and clears it.
    private func watchWait() {
        guard isWaiting else {
            waitWatch?.cancel()
            waitWatch = nil
            return
        }
        guard waitWatch == nil else { return }
        let clock = waitClock
        waitWatch = Task { [weak self] in
            do { try await clock(Self.waitLimit) } catch { return }
            guard !Task.isCancelled else { return } // a wait that ended meanwhile; a newer one has its own watch
            self?.waitDidExpire()
        }
    }

    /// The screen shows "Chargement des messages": no error, and no page yet or a page the web view has not shown.
    private var isWaiting: Bool {
        error == nil && (page.map { !$0.messages.isEmpty && readyToken == nil } ?? true)
    }

    private func waitDidExpire() {
        waitWatch = nil
        guard isWaiting else { return }
        ReaderLog.debug("wait expired model=\(debugID) loading=\(isLoading) document=\(document?.token ?? -1)")
        if page != nil, let document { failedToken = document.token }
        waitExpired = true
        error = .timedOut
        if task != nil { cancel() } // after `error`: the load's own watch must not start again
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
        failedToken = nil // this load owns `error` now: an old document's ready must not clear its failure
        waitExpired = false
        watchWait()
        ReaderLog.debug("load start model=\(debugID) generation=\(mine) page=\(target.page)")
        let source = self.source
        let task = Task { [weak self] in
            var result = await TopicReaderModel.fetch(target, from: source)
            // A cancellation nobody asked for (`cancel()` and a newer load cancel this task): asked once more (issue #566).
            if case .failure(.cancelled) = result, !Task.isCancelled {
                result = await TopicReaderModel.fetch(target, from: source)
            }
            self?.finish(result, target: target, keepsScrollPosition: keepsScrollPosition, anchor: rule, generation: mine)
        }
        self.task = task
        await task.value
        return generation == mine
    }

    nonisolated private static func fetch(
        _ target: ReaderTarget, from source: any TopicPageSource
    ) async -> Result<ReaderPage, ListLoadError> {
        do throws(ListLoadError) {
            return .success(try await source.page(for: target))
        } catch {
            return .failure(error)
        }
    }

    private func finish(
        _ result: Result<ReaderPage, ListLoadError>, target: ReaderTarget, keepsScrollPosition: Bool, anchor rule: AnchorRule,
        generation mine: Int
    ) {
        ReaderLog.debug(
            "load finish model=\(debugID) generation=\(mine) current=\(mine == generation) success=\(result.isSuccess)"
        )
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
            // The topic is open: a draft legacy kept for its number becomes its reply draft (LOT-067 D1).
            if let legacyDrafts, let topic = loaded.topicID { legacyDraftTask = Task { await legacyDrafts.resolve(topic) } }
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
        case .failure(let failure):
            // A cancellation that reaches here was not asked for and came twice: an error, never a screen left waiting with
            // no page, no load and no error (issue #566).
            error = failure == .cancelled ? .other : failure
        }
        applyDisplaySettings() // a setting changed while this load ran and did not deliver a page
        watchWait()
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
