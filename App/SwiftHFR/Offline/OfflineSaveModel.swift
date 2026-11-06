import Foundation
import HFRModels
import HFRStorage
import Observation

// Port of Classes/OfflineStorage.m (the download, `:145-294`, commented out) @ 2440d79: the save side that legacy never
// shipped. Differences: every page is fetched without cookies (no flag moves, LOT-045), an explicit "save this page and the
// next ones" action, a reason when a page is refused (GAP-180, LOT-139).
/// Saves a topic's pages for offline reading: one page after the other, so a failure keeps what was saved before it.
@MainActor
@Observable
final class OfflineSaveModel {
    /// Where a save stands.
    enum State: Equatable {
        case idle
        /// `done` of `total` pages are saved.
        case saving(done: Int, total: Int)
        case finished(saved: Int)
        /// Stopped by the member after `saved` pages.
        case stopped(saved: Int)
        /// Stopped by a failure after `saved` pages; `message` is shown to the member.
        case failed(message: String, saved: Int)
    }

    /// What the screen shows.
    private(set) var state = State.idle

    private let store: any OfflineStoring
    private let fetcher: any OfflinePageFetching
    private let now: @Sendable () -> Date
    private var task: Task<Void, Never>?

    init(store: any OfflineStoring, fetcher: any OfflinePageFetching, now: @escaping @Sendable () -> Date = { .now }) {
        self.store = store
        self.fetcher = fetcher
        self.now = now
    }

    /// A save is running.
    var isSaving: Bool {
        if case .saving = state { return true }
        return false
    }

    /// Saves `count` pages from the one on screen (fewer at the end of the topic), titled with the page's title, or `fallbackTitle`
    /// when HFR gave none. A private conversation or a page without a topic is ignored.
    func save(page: ReaderPage, count: Int, fallbackTitle: String) async {
        await begin(page: page, count: count, fallbackTitle: fallbackTitle)?.value
    }

    /// Starts the same run without waiting for it, held by this model so `leave()` can stop it; the run exists when this returns.
    /// The save button is the only thing that starts one: nothing restarts a run when a screen reappears.
    func start(page: ReaderPage, count: Int, fallbackTitle: String) {
        begin(page: page, count: count, fallbackTitle: fallbackTitle)
    }

    @discardableResult
    private func begin(page: ReaderPage, count: Int, fallbackTitle: String) -> Task<Void, Never>? {
        guard let topic = page.topicID else { return nil }
        let last = min(page.currentPage + max(1, count) - 1, page.maxPage)
        return begin(
            topic: topic, title: page.title.isEmpty ? fallbackTitle : page.title, pages: page.currentPage...max(page.currentPage, last)
        )
    }

    /// The member left the topic (not merely covered it by a linked reader or the image viewer): stop after the page in progress.
    /// What was saved stays.
    func leave() {
        task?.cancel()
    }

    /// Saves `pages` of `topic`, returning when done, failed or stopped. Ignored while another save runs.
    func save(topic: TopicID, title: String, pages: ClosedRange<Int>) async {
        await begin(topic: topic, title: title, pages: pages)?.value
    }

    private func begin(topic: TopicID, title: String, pages: ClosedRange<Int>) -> Task<Void, Never>? {
        guard !isSaving, pages.lowerBound >= 1 else { return nil }
        state = .saving(done: 0, total: pages.count)
        let task = Task {
            let outcome = await self.run(pages, of: topic, title: title)
            self.finish(outcome)
            // Past 200 MB the pages saved longest ago go (ADR 0013, LOT-066): the budget is applied after each run and at launch.
            await self.store.evict()
        }
        self.task = task
        return task
    }

    private func run(_ pages: ClosedRange<Int>, of topic: TopicID, title: String) async -> State {
        var saved = 0
        for number in pages {
            if Task.isCancelled { return .stopped(saved: saved) }
            switch await savePage(number, of: topic, title: title) {
            case .saved: break
            case .stopped: return .stopped(saved: saved)
            case .failed(let message): return .failed(message: message, saved: saved)
            }
            saved += 1
            state = .saving(done: saved, total: pages.count)
        }
        return .finished(saved: saved)
    }

    private enum PageResult {
        case saved, stopped
        case failed(String)
    }

    private func savePage(_ number: Int, of topic: TopicID, title: String) async -> PageResult {
        do throws(ListLoadError) {
            let fetched = try await fetcher.fetch(topic: topic, page: number)
            do throws(OfflineStoreError) {
                try await store.save(OfflinePage(topic: topic, page: fetched.page, title: title, html: fetched.html, savedAt: now()))
            } catch {
                return .failed(error.message)
            }
            return .saved
        } catch {
            return error == .cancelled ? .stopped : .failed(error.detail)
        }
    }

    /// Stops after the page being saved.
    func cancel() {
        task?.cancel()
    }

    /// Forgets a finished save's outcome (the banner was dismissed).
    func dismiss() {
        if !isSaving { state = .idle }
    }

    private func finish(_ outcome: State) {
        state = outcome
        task = nil
    }
}
