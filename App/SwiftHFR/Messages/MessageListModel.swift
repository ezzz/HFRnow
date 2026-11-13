import Foundation
import HFRModels
import HFRParsing
import HFRStorage
import Observation

/// Which conversations the "Deux listes" switch shows (LOT-171).
enum MPSegment: String, CaseIterable, Sendable {
    /// One-to-one conversations ("MP").
    case oneToOne
    /// Group conversations ("MP multiples").
    case group

    /// Switch label.
    var title: String { self == .oneToOne ? "MP" : "MP multiples" }

    /// Whether `thread` belongs to this segment (`PrivateMessageThread.isGroup`, legacy `MPListView.swift:376-377`).
    func contains(_ thread: PrivateMessageThread) -> Bool { thread.isGroup == (self == .group) }
}

/// A private message list page ready to display.
struct MessageListContent: Sendable, Equatable {
    /// Conversations in page order. Each row keeps its own unread state and group flag, so a later lot can split or count
    /// them without fetching again (LOT-171).
    var threads: [PrivateMessageThread]
    /// Page shown (1-based).
    var page: Int
    /// A next page exists. The pager is a window, so only "there is a next page" is known, never a total.
    var hasNext: Bool
    /// Why there is no row, when there is none.
    var emptyReason: EmptyReason?
    /// The page's "new private message" link (`md_btn_new_topic`, `R13a`), resolved on the forum; nil when absent.
    var newMessageURL: URL?

    /// Conversations of this page the member has not read; the mailbox total is the badge's (home page), not this.
    var unreadCount: Int { threads.filter(\.isUnread).count }

    init(threads: [PrivateMessageThread], page: Int, hasNext: Bool, emptyReason: EmptyReason?, newMessageURL: URL? = nil) {
        self.threads = threads
        self.page = page
        self.hasNext = hasNext
        self.emptyReason = emptyReason
        self.newMessageURL = newMessageURL
    }

    init(page list: PrivateMessageListPage) {
        threads = list.threads
        page = list.navigation.current
        hasNext = list.navigation.nextPath != nil
        emptyReason = list.threads.isEmpty ? .nothing : nil
        newMessageURL = list.newMessagePath.flatMap { HFRURL.absolute($0) }
    }

    /// What a logged-out visitor sees: no request is made, the list asks for a login.
    static let signedOut = MessageListContent(threads: [], page: 1, hasNext: false, emptyReason: .signInRequired(nil))
}

// Port of HFRswift/Swift/MPListView.swift (MPListViewModel; hasMultipleInterlocutors, :376-377) @ 2440d79.
// Differences: one page at a time (LOT-023, LOT-045), the group test is `PrivateMessageThread.isGroup`, and the split
// (setting "Affichage des MP", switch "MP" / "MP multiples") has no legacy counterpart: operator decision
// 2026-10-28, see docs/lots/LOT-171-mp-lists.md.
/// State of the private message list (LOT-126): one page at a time, the conversation opened in the reader.
///
/// Same loading rules as the topic lists (one load at a time, rows kept while reloading or after a failure, refresh reloads
/// the page on screen). Logged out, nothing is requested: the list says a login is needed.
@MainActor
@Observable
final class MessageListModel {
    let loader = ContentLoader<MessageListContent>()
    /// Conversation chosen in the list, shown by the reader.
    var selected: PrivateMessageThread? {
        // Leaving the conversation drops its reader, so opening it again fetches the current messages.
        didSet { if selected == nil { currentReader = nil } }
    }

    /// "Tout en un" or "Deux listes" (`mp_list_display`); the screen sets it from the settings. Only `.split` filters.
    var display: MPListDisplay = .single
    /// The switch position when `display` is `.split`.
    var segment: MPSegment = .oneToOne
    /// Pages after the first that a segment's search may load by itself, so an empty segment cannot walk a whole mailbox.
    static let maxAutoAdvance = 5

    /// Page of the last load that was asked for; a retry after a failure goes back to it.
    private(set) var requestedPage = 1
    /// HFR's confirmation of the private message just sent (LOT-128) or of a conversation marked unread (LOT-127), shown
    /// until dismissed.
    private(set) var sentConfirmation: String?
    /// Why a "Marquer comme non lu" failed once its reader was gone; a reader on screen says it itself.
    var actionFailure: String?

    /// MPStorage sync of the current account (LOT-130), for the group rows' flags; nil when logged out.
    let mpStorage: MPStorageSyncModel?
    /// The Messages badge's count, moved by one when a conversation is read or marked unread here (#762); nil in tests that
    /// do not need it.
    private let privateMessageCount: PrivateMessageCount?

    private let source: any PrivateMessageSource
    private let isLoggedIn: @Sendable () async -> Bool
    private let topicPages: any TopicPageSource
    private let renderOptions: @Sendable () -> ReaderRenderOptions
    /// Where `mp_list_display` is read each time the list appears (the Réglages screen writes it); nil keeps `display` as set.
    private let settings: (any SettingsStore)?
    /// Threads whose last page was shown, each with the number of the load that was the newest when it was opened. A load
    /// brings HFR's own state back only for the threads opened before it started.
    private var openedThreads: [String: Int] = [:]
    /// Threads HFR confirmed unread: the page on screen predates the write, so the row shows unread until a load answers. The
    /// reload that follows the confirmation supersedes any older load, so the next load applied started after it (LESSONS 57).
    private var markedUnread: Set<String> = []
    /// Loads started so far; tells a load that is still the newest from one that was superseded.
    private var loadCount = 0
    /// The reader of the selected conversation, created once per selection so a view update never refetches the page (E25).
    @ObservationIgnored private var currentReader: (id: String, model: TopicReaderModel)?

    /// Creates the model; `isLoggedIn` is read when a load starts.
    init(
        source: any PrivateMessageSource,
        isLoggedIn: @escaping @Sendable () async -> Bool = { false },
        topicPages: any TopicPageSource = UnavailableTopicPages(),
        renderOptions: @escaping @Sendable () -> ReaderRenderOptions = { ReaderRenderOptions() },
        settings: (any SettingsStore)? = nil,
        mpStorage: MPStorageSyncModel? = nil,
        privateMessageCount: PrivateMessageCount? = nil
    ) {
        self.mpStorage = mpStorage
        self.privateMessageCount = privateMessageCount
        self.settings = settings
        self.source = source
        self.isLoggedIn = isLoggedIn
        self.topicPages = topicPages
        self.renderOptions = renderOptions
    }

    /// The rows of the page on screen for the current display: all of them, or only the segment's.
    var visibleThreads: [PrivateMessageThread] {
        let threads = loader.value?.threads ?? []
        return display == .split ? threads.filter(segment.contains) : threads
    }

    /// Unread rows of `segment` on the page on screen (HFR's state plus what was opened here); page-bounded like
    /// `MessageListContent.unreadCount`. The tab badge stays the mailbox total (LOT-170).
    func unreadCount(in segment: MPSegment) -> Int {
        (loader.value?.threads ?? []).filter { segment.contains($0) && isUnread($0) }.count
    }

    /// The switch moved. No server filter of the MP list is known, so when the page on screen holds nothing of the new segment
    /// while later pages exist, the next pages are loaded (bounded) instead of showing an empty list.
    func select(_ segment: MPSegment) async {
        chooseSegment(segment)
        await searchForSegment()
    }

    /// The synchronous part of a switch change, applied in the order the member made the changes: the position, the
    /// conversation it hides, and the stop of a search running for the previous position. The search itself is
    /// `searchForSegment()`, which always reads the latest position, so an older task can never restore an older segment.
    func chooseSegment(_ segment: MPSegment) {
        self.segment = segment
        dropSelectionHiddenBySegment()
        // A search for the previous segment is stopped, not left to walk on for this one.
        // `loadCount` moves too, so the cancelled load's own follow-up (openedThreads, signed-out check) is dropped.
        if isSearchingSegment {
            loadCount += 1
            loader.cancel()
        }
    }

    /// Looks for rows of the current segment in later pages when the page on screen has none (bounded).
    func searchForSegment() async { await advanceWhileSegmentEmpty() }

    /// Whether the "MP" / "MP multiples" switch is shown: a split list that has rows (not logged out, not an empty mailbox).
    var showsSegmentSwitch: Bool { display == .split && loader.value.map { !$0.threads.isEmpty } == true }

    /// The reader must not keep showing a conversation the list no longer offers (iPad, regular width).
    private func dropSelectionHiddenBySegment() {
        if display == .split, let selected, !segment.contains(selected) { self.selected = nil }
    }

    /// True while that search for the segment's rows runs, so the screen shows progress, not "empty".
    private(set) var isSearchingSegment = false
    /// Searches started so far; a search stops when a newer one has started.
    private var searchCount = 0

    /// Loads the next pages while the segment has no row on screen, a next page exists and the bound is not reached.
    /// Stops at once when anything else loaded meanwhile (a pull to refresh, a pager tap) or a load failed.
    private func advanceWhileSegmentEmpty() async {
        var steps = 0
        let start = loadCount
        searchCount += 1
        let token = searchCount
        isSearchingSegment = true
        // Only the newest search clears the flag: an older one ending late must not hide a running one.
        defer { if token == searchCount { isSearchingSegment = false } }
        while token == searchCount, display == .split, !loader.isLoading, loader.error == nil, visibleThreads.isEmpty,
              loader.value?.hasNext == true, steps < Self.maxAutoAdvance, loadCount == start + steps {
            steps += 1
            await load(page: currentPage + 1, advancing: false)
        }
    }

    /// Page on screen; 1 before the first load.
    var currentPage: Int { loader.value?.page ?? 1 }
    var canGoToPrevious: Bool { currentPage > 1 && !loader.isLoading }
    var canGoToNext: Bool { (loader.value?.hasNext ?? false) && !loader.isLoading }

    /// The list became visible: first load, or a refresh, because reading a conversation elsewhere changes its unread state.
    /// Rows stay meanwhile.
    func onAppear() async {
        if let settings { display = settings.value(for: SettingKey.mpListDisplay) }
        dropSelectionHiddenBySegment()
        guard !loader.isLoading else { return }
        await load(page: loader.value == nil ? 1 : currentPage)
    }

    /// Reloads the page on screen.
    func refresh() async { await load(page: currentPage) }

    /// Asks again for the last page that was asked for (after a failure).
    func retry() async { await load(page: requestedPage) }

    func goToNextPage() async { if canGoToNext { await load(page: currentPage + 1) } }
    /// Going back never searches forward: the member asked for that page.
    func goToPreviousPage() async { if canGoToPrevious { await load(page: currentPage - 1, advancing: false) } }
    func goToFirstPage() async { if canGoToPrevious { await load(page: 1) } }

    /// The reader of `thread`: the same model while it stays selected, a new one (a new load) for another conversation.
    /// Nil when the row names no thread page.
    func reader(for thread: PrivateMessageThread) -> TopicReaderModel? {
        if let currentReader, currentReader.id == thread.id { return currentReader.model }
        guard let opening = openingTarget(of: thread) else { return nil }
        let model = TopicReaderModel(
            target: opening.target, title: thread.summary.title, source: topicPages,
            opensAtLastMessage: opening.fromLatestMessage, renderOptions: renderOptions
        )
        currentReader = (thread.id, model)
        return model
    }

    /// Where a row opens: the page of its latest message (legacy tap, `HFRMPViewController.m:255`), so a conversation with
    /// new messages shows them. MP rows carry no HFR flag link (`sujetCase5` is empty, `R13u1`). The reader then opens at the
    /// page's last message, as the link's `#bas` does in legacy (`OnlineMessagesTableViewController.m:1838,2050`). A row
    /// without a usable latest-message link opens like any topic row. A group row does not open at its MPStorage flag yet
    /// (legacy `HFRMPViewController.m:228-251` @ 87fe0d1c): SwiftHFR does not move the flag while reading, so a flag nobody
    /// moves would open an old page forever; the opening comes with the reader's flag write (LOT-130 spec, Out of scope).
    private func openingTarget(of thread: PrivateMessageThread) -> (target: ReaderTarget, fromLatestMessage: Bool)? {
        if let last = thread.summary.lastPost?.path,
           let target = ReaderTarget(link: last, fallbackTopic: thread.summary.topicID) {
            return (target, true)
        }
        guard let target = ReaderTarget(opening: thread.summary) else { return nil }
        return (target, false)
    }

    /// The group row's MPStorage flag as legacy wrote it, `⚑ <page> / <max>` (`MPListView.swift:775-786` @ 87fe0d1c), max being
    /// at least the flag's page (`:368`); nil without a flag (one-to-one rows, MPStorage off, no document yet).
    func flagLabel(for thread: PrivateMessageThread) -> String? {
        guard let page = mpStorage?.flag(for: thread)?.page else { return nil }
        let current = max(page, 1)
        return "⚑ \(current) / \(max(thread.summary.pageCount, current))"
    }

    /// The new-MP composer the page on screen links to (legacy `newTopic` on the MP list, `TopicsTableViewController.m:222-245`
    /// with `forumNewTopicUrl` read from `md_btn_new_topic`, `ObjCTopicListParser.m:133-135` @ 21173e77); nil before a load,
    /// logged out (no request, no page) or when the page has no such link.
    var newMessageTarget: NewMessageTarget? {
        loader.value?.newMessageURL.flatMap(NewMessageTarget.init(link:))
    }

    /// The new-MP sheet closed. After HFR's confirmation (`W10`: it names no thread and refreshes to the list), page 1 is
    /// reloaded and the thread opens when exactly one row of it bears the subject sent (`R13a`, the list after `W10`, shows
    /// the thread under that subject); otherwise the list stays. After an unconfirmed send, page 1 is reloaded so the user
    /// sees whether it went. Closing with or without the draft changes nothing.
    func newMessageDidClose(_ reason: ReplyComposerModel.CloseReason, subject: String) async {
        switch reason {
        case .sent(let result):
            sentConfirmation = result.message
            // The reload must stay on page 1: a search for the segment could move past the row just sent.
            await load(page: 1, advancing: false)
            let sent = subject.trimmingCharacters(in: .whitespacesAndNewlines)
            guard loader.error == nil, let threads = loader.value?.threads else { return }
            let matches = threads.filter { $0.summary.title == sent }
            if matches.count == 1, let match = matches.first {
                // The row must stay visible: show the segment it belongs to.
                if display == .split { segment = match.isGroup ? .group : .oneToOne }
                selected = match
            }
        case .checkTopic:
            await load(page: 1)
        case .keptDraft, .discardedDraft, .closedWithoutSaving:
            break
        }
    }

    /// Hides the confirmation of the private message just sent.
    func clearSentConfirmation() {
        sentConfirmation = nil
    }

    /// Whether the row shows as unread: HFR's state, until the member has seen the conversation's last page; or marked
    /// unread here, until a later load says what HFR holds.
    func isUnread(_ thread: PrivateMessageThread) -> Bool {
        markedUnread.contains(thread.id) || (thread.isUnread && openedThreads[thread.id] == nil)
    }

    /// "Marquer comme non lu" ended in `reader`, a reader of `thread` (LOT-127). HFR's confirmation closes the conversation and reloads
    /// the list, as legacy pops and refetches (`OnlineMessagesTableViewController.m:900-903`): keeping the reader would show a
    /// thread HFR now holds unread, and its next load could read it again. A failure changes nothing on the row.
    func markUnreadEnded(_ thread: PrivateMessageThread, in reader: TopicReaderModel, _ outcome: TopicFlagOutcome) async {
        switch outcome {
        case .failed(let reason):
            // Only the reader that sent it holds the failure: the same conversation opened again has a new one, which shows nothing.
            if currentReader?.model !== reader { actionFailure = reason }
        case .done(let message):
            sentConfirmation = message
            // Legacy adds one for a row that showed read (`MPListView.swift:536-540` @ 87fe0d1c).
            if !isUnread(listed(thread)) { privateMessageCount?.adjust(by: 1) }
            markedUnread.insert(thread.id)
            if selected?.id == thread.id { selected = nil }
            await refresh()
        }
    }

    /// Remembers that the reader shows page `page` of `pageCount` of `thread`, so its row is shown read without a request.
    /// Only the last page counts: earlier pages leave newer messages unseen. A row that names no thread page opens nothing,
    /// so it stays unread. What HFR itself does on a thread page fetch is not captured (spec, pending capture), hence this
    /// is a local display state only; the next load brings HFR's own state back.
    func markOpened(_ thread: PrivateMessageThread, page: Int, of pageCount: Int) {
        guard page >= pageCount, openingTarget(of: thread) != nil else { return }
        // Legacy takes one off the badge for a row that showed unread (`MPListView.swift:497-502` @ 87fe0d1c): once per read.
        if isUnread(listed(thread)) { privateMessageCount?.adjust(by: -1) }
        openedThreads[thread.id] = loadCount
        markedUnread.remove(thread.id)
    }

    /// The row the list holds now for `thread`'s conversation, else `thread`: the reader keeps the value of the tap, which a
    /// later load may have made stale (a row since read must not take a second one off the badge, #762).
    private func listed(_ thread: PrivateMessageThread) -> PrivateMessageThread {
        loader.value?.threads.first { $0.id == thread.id } ?? thread
    }

    private func load(page: Int, advancing: Bool = true) async {
        requestedPage = page
        loadCount += 1
        let mine = loadCount
        let source = source
        let isLoggedIn = isLoggedIn
        await loader.load { () async throws(ListLoadError) -> MessageListContent in
            guard await isLoggedIn() else { return .signedOut }
            return MessageListContent(page: try await source.privateMessages(page: page))
        }
        // Only the newest load applied the content on screen; a superseded one returning late must not reset the state.
        guard mine == loadCount else { return }
        if let error = loader.error {
            // HFR refused the session while the cookie is still there: same as an expired one, the reader must not stay open.
            if case .notAuthenticated = error { selected = nil }
            return
        }
        // Threads opened while this load was running were not in its answer: they stay read until the next load.
        openedThreads = openedThreads.filter { $0.value >= mine }
        markedUnread.removeAll()
        // A session that expired while a conversation was open: the list asks for a login, the reader must not keep showing it.
        if loader.value == .signedOut { selected = nil }
        if advancing { await advanceWhileSegmentEmpty() }
    }
}
