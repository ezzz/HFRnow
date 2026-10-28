import Foundation
import HFRModels
import Observation

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

/// What the reader does with a link the user tapped.
enum ReaderLinkAction: Equatable, Sendable {
    /// A topic page of the forum: opened in the reader, at its page and post.
    case reader(ReaderTarget)
    /// Anything else on the web: opened outside the reader (`SFSafariViewController`, LOT-071 T8).
    case external(URL)
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
    /// HFR's confirmation of the reply just sent, shown until dismissed; set only by a confirmed reply (LOT-084).
    private(set) var replyConfirmation: String?
    /// Title until the page gives its own.
    let initialTitle: String

    /// The page last asked for (shown, or failed): what "Réessayer" asks again.
    private(set) var requested: ReaderTarget
    /// Where the page last asked for opens, kept so "Réessayer" after a failed latest-post load still opens at the end.
    private var requestedAnchor = AnchorRule.target
    /// The target of the page on screen (topic and page as served), what a refresh reloads.
    private(set) var shown: ReaderTarget?

    private let source: any TopicPageSource
    private let renderOptions: @Sendable () -> ReaderRenderOptions
    private var generation = 0
    private var nextToken = 0
    private var nextScrollID = 0
    private var task: Task<Void, Never>?

    /// A reader that will open `target`; nothing is fetched before `onAppear()`.
    init(
        target: ReaderTarget,
        title: String = "",
        source: any TopicPageSource,
        renderOptions: @escaping @Sendable () -> ReaderRenderOptions = { ReaderRenderOptions() }
    ) {
        self.requested = target
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

    /// Asks again for the page that failed.
    func retry() async {
        await load(requested, keepsScrollPosition: false, anchor: requestedAnchor)
    }

    /// Opens page `number` of the topic (clamped to the known pages).
    func goToPage(_ number: Int) async {
        guard let shown, let page else { return }
        let clamped = min(max(1, number), page.maxPage)
        await load(shown.atPage(clamped), keepsScrollPosition: false)
    }

    /// Whether a previous page exists.
    var canGoToPrevious: Bool { (page?.currentPage ?? 1) > 1 }
    /// Whether a next page exists.
    var canGoToNext: Bool { page.map { $0.currentPage < $0.maxPage } ?? false }

    /// Opens another target in this reader (a link to a topic or a post).
    func open(_ target: ReaderTarget) async {
        if let shown, let page, let anchor = target.anchor, isSameTopic(target, as: shown), target.page == page.currentPage,
           let document, page.messages.contains(where: { !$0.isContinuation && $0.numreponse == anchor }) {
            nextScrollID += 1
            scrollRequest = ScrollRequest(id: nextScrollID, token: document.token, anchor: anchor)
            return
        }
        await load(target, keepsScrollPosition: false)
    }

    /// What the reply composer needs from the page on screen; nil when the page offers no answer form (logged out, locked
    /// topic: `#repondre_form` is absent, LOT-033) or names no topic (the draft is kept per topic).
    var replyTarget: ReplyTarget? {
        // Same origin rule as `PostingFlow`: a link it would refuse (another port) offers no reply.
        guard let page, let formURL = page.answerURL, formURL.port == nil || formURL.port == 443,
              let topic = page.topicID else { return nil }
        return ReplyTarget(formURL: formURL, topic: topic, title: title)
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
        case .keptDraft, .discardedDraft:
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
    /// HFR's own refresh names page 1 (`W30`: `…_1.htm#bas`), so it is not followed.
    func showLatestPost() async {
        guard let page, let shown else { return }
        await load(shown.atPage(page.maxPage + 1), keepsScrollPosition: false, anchor: .lastMessage)
    }

    /// Stops the load in flight; the content stays.
    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
        isLoading = false
    }

    /// The web view reports a document as ready; an older document's report is ignored.
    func documentDidBecomeReady(token: Int) {
        guard token == document?.token else { return }
        readyToken = token
    }

    /// What tapping `url` does. Forum topic links open in the reader, keeping page and post (issue #106).
    func action(forLink url: URL) -> ReaderLinkAction {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return .ignored }
        if let target = ReaderTarget(link: url.absoluteString, fallbackTopic: page?.topicID) { return .reader(target) }
        return .external(url)
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

    private func load(_ target: ReaderTarget, keepsScrollPosition: Bool, anchor rule: AnchorRule = .target) async {
        task?.cancel()
        generation += 1
        let mine = generation
        requested = target
        requestedAnchor = rule
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
            document = ReaderDocument(
                token: nextToken,
                html: TopicHTMLBuilder.document(for: loaded, token: nextToken, options: renderOptions()),
                anchor: anchor,
                keepsScrollPosition: keepsScrollPosition && anchor == nil
            )
        case .failure(.cancelled):
            break
        case .failure(let failure):
            error = failure
        }
    }

    private func isSameTopic(_ target: ReaderTarget, as shown: ReaderTarget) -> Bool {
        switch (target.source, shown.source) {
        case (.topic(let lhs), .topic(let rhs)): lhs == rhs
        default: false
        }
    }
}
