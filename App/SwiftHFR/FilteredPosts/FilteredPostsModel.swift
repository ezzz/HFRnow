import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRParsing
import Observation

/// One batch of filtered messages as the filtered view shows it (legacy `FavoritePostFilterResult`,
/// `HFRswift/Swift/FavoritePostFilterService.swift:21-49` @ 2440d79).
struct FilteredPostsResult: Equatable, Sendable {
    /// The topic filtered.
    let topic: TopicID
    /// The kept messages, normalized, as one reader page (`currentPage` is the last page read).
    let page: ReaderPage
    /// First and last page read for this batch.
    let startPage: Int
    let endPage: Int
    /// The topic's last page.
    let maxPage: Int
    /// The last page of the topic was read: there is nothing after this batch.
    let isFinished: Bool

    /// Messages kept in this batch.
    var count: Int { page.messages.count }

    /// Legacy's subtitle: "N posts | 3" or "N posts | 3 à 5".
    var subtitle: String {
        let pages = startPage == endPage ? "\(startPage)" : "\(startPage) à \(endPage)"
        return "\(FilteredPostsModel.countText(count)) | \(pages)"
    }

    /// The batch with nothing left after it.
    func markingFinished() -> FilteredPostsResult {
        FilteredPostsResult(
            topic: topic, page: page, startPage: startPage, endPage: endPage, maxPage: maxPage, isFinished: true
        )
    }
}

/// The post filter's state (LOT-114): a run from a favourite or the reader, its progress, the batch shown and "Résultats
/// suivants". The pages are read by `FilteredPostsSource` (LOT-093), cookie-less.
///
/// One run at a time. Cancelling a run leaves what is shown: a first run that is cancelled shows nothing, a later one keeps
/// the batch on screen. A cancelled or superseded run never delivers (same rule as the reader's loads, issue #108).
@MainActor
@Observable
final class FilteredPostsModel {
    /// Where the first run of a topic stands; nil when no run is in progress or after "Résultats suivants" (which has its
    /// own flag).
    private(set) var progress: FilteredPostsProgress?
    /// A first run (from the list or the reader menu) is reading pages.
    private(set) var isRunning = false
    /// The batch shown by the filtered view; setting it nil closes the view.
    private(set) var result: FilteredPostsResult?
    /// "Résultats suivants" is reading pages.
    private(set) var isAdvancing = false
    /// An information the user dismisses (legacy `favoritePostFilterStatusMessage`, "Aucun post n'a été trouvé").
    private(set) var statusMessage: String?
    /// A failure, shown in an alert (legacy "Filtre impossible").
    private(set) var errorMessage: String?
    /// Title of the topic being filtered.
    private(set) var title = ""

    private let services: FilteredPostsServices
    private var task: Task<Void, Never>?
    /// The latest run's task, kept after it ends or is cancelled so a test can wait for a stale run (test seam).
    private(set) var lastRun: Task<Void, Never>?
    private var generation = 0

    /// Creates a model over `services`.
    init(services: FilteredPostsServices = .unavailable) {
        self.services = services
    }

    /// Legacy's "N post(s)".
    nonisolated static func countText(_ count: Int) -> String {
        count <= 1 ? "\(count) post" : "\(count) posts"
    }

    /// Legacy's progress line: "N posts | page X/Y" (`FavoritePostFilterService.swift:10-19`).
    nonisolated static func statusText(_ progress: FilteredPostsProgress) -> String {
        "\(countText(progress.resultCount)) | page \(progress.page)/\(max(progress.maxPage, 1))"
    }

    /// A run is reading pages (first run or "Résultats suivants"): another cannot start.
    var isBusy: Bool { isRunning || isAdvancing }

    /// The line the progress banner shows.
    var bannerText: String? {
        if let statusMessage { return statusMessage }
        return progress.map(Self.statusText)
    }

    /// What "Résultats suivants" does, for the button's hint: the filtering goes on from the next unread page.
    var nextBatchHint: String? {
        guard let result, !result.isFinished else { return nil }
        return "Lit les pages suivantes à partir de la page \(result.endPage + 1) et affiche les prochains posts retenus."
    }

    // MARK: - First run

    /// Filters the topic `topic` from where the user stopped reading: the row's resume page and message (legacy
    /// `topic.curTopicPage` and the `#t<id>` of the favourite link, `FilterPostsQuotes.m:219-243`). Ignored while a run is
    /// going.
    func start(opening topic: TopicSummary) {
        guard let target = ReaderTarget(opening: topic), let id = topic.topicID ?? Self.topicID(of: target) else {
            errorMessage = Self.message(for: .invalidTopic)
            return
        }
        // A `numreponse` link names no page (issue #106): the row's own page is the best start.
        let page = target.numreponse == nil ? target.page : max(topic.currentPage ?? 1, 1)
        start(topic: id, title: topic.displayTitle, page: page, after: target.anchor ?? target.numreponse, knownMaxPage: topic.pageCount)
    }

    /// Filters `topic` from `page`, skipping the messages up to `message` on that page.
    func start(topic: TopicID, title: String, page: Int, after message: Int?, knownMaxPage: Int? = nil) {
        guard !isRunning, !isAdvancing else { return }
        statusMessage = nil
        errorMessage = nil
        self.title = title
        isRunning = true
        progress = FilteredPostsProgress(page: max(page, 1), maxPage: max(knownMaxPage ?? page, page, 1), resultCount: 0)
        run { [self] id in
            let outcome = await read(topic: topic, page: page, after: message, run: id)
            guard id == generation else { return }
            isRunning = false
            progress = nil
            switch outcome {
            case .success(let batch):
                guard let batch else { return }
                if batch.page.messages.isEmpty {
                    statusMessage = "Aucun post n'a été trouvé"
                } else {
                    result = batch
                }
            case .failure(let error):
                errorMessage = Self.message(for: error)
            }
        }
    }

    // MARK: - Next batch

    /// "Résultats suivants": the next batch from the page after the one shown. No batch left means the topic is finished
    /// (legacy toast "Aucun autre post trouvé"); a failure or a cancellation leaves the batch shown.
    func showNextBatch() {
        guard let shown = result, !shown.isFinished, !isRunning, !isAdvancing else { return }
        errorMessage = nil
        isAdvancing = true
        run { [self] id in
            let outcome = await read(topic: shown.topic, page: shown.endPage + 1, after: nil, run: id)
            guard id == generation else { return }
            isAdvancing = false
            switch outcome {
            case .success(let batch):
                guard let batch else { return }
                if batch.page.messages.isEmpty {
                    result = shown.markingFinished()
                    statusMessage = "Aucun autre post trouvé"
                } else {
                    result = batch
                }
            case .failure(let error):
                errorMessage = Self.message(for: error)
            }
        }
    }

    // MARK: - Control

    /// Stops the run in flight. A first run leaves nothing on screen; "Résultats suivants" leaves the batch shown.
    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
        isRunning = false
        isAdvancing = false
        progress = nil
    }

    /// Closes the filtered view (and stops anything it was reading).
    func closeResult() {
        cancel()
        result = nil
        statusMessage = nil
    }

    /// Hides the information line.
    func dismissStatus() {
        statusMessage = nil
    }

    /// Hides the failure alert.
    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Reading

    private func run(_ body: @escaping @MainActor (Int) async -> Void) {
        task?.cancel()
        generation += 1
        let mine = generation
        let run = Task { await body(mine) }
        task = run
        lastRun = run
    }

    private func report(_ progress: FilteredPostsProgress, run id: Int) {
        // Only the first run has a banner; a stale run's report is dropped.
        guard id == generation, isRunning else { return }
        self.progress = progress
    }

    /// The batch from `page`, normalized; `.success(nil)` when the run was cancelled.
    private func read(
        topic: TopicID, page: Int, after message: Int?, run id: Int
    ) async -> Result<FilteredPostsResult?, FilteredPostsError> {
        let services = self.services
        await services.prepare()
        let criteria = services.criteria()
        do throws(FilteredPostsError) {
            let batch = try await services.source.batch(in: topic, from: page, after: message, criteria: criteria) { [weak self] progress in
                await self?.report(progress, run: id)
            }
            if Task.isCancelled { return .success(nil) }
            return .success(try await Self.result(of: batch, topic: topic, title: title, normalizer: services.normalizer))
        } catch {
            // A cancelled run is not an error to show.
            if case .network(.cancelled) = error { return .success(nil) }
            return .failure(error)
        }
    }

    /// The batch as a reader page: every kept message normalized like the reader's (ADR 0006), in page order.
    @concurrent static func result(
        of batch: FilteredPostsBatch, topic: TopicID, title: String, normalizer: any MessageContentNormalizing
    ) async throws(FilteredPostsError) -> FilteredPostsResult {
        let base = HFRURL.base
        var messages: [ReaderMessage] = []
        messages.reserveCapacity(batch.posts.count)
        for post in batch.posts {
            // A cancelled run stops sanitizing; `read` turns this into "nothing to show".
            if Task.isCancelled { throw .network(.cancelled) }
            let block = post.block
            let content: MessageContent
            do throws(ParsingError) {
                content = try normalizer.normalize(contentHTML: block.contentHTML, pageURL: base)
            } catch {
                throw .page(error)
            }
            messages.append(ReaderMessage(
                numreponse: block.numreponse, author: block.author, isDeleted: block.isDeleted, isContinuation: false,
                avatarURL: block.avatarURL, dateText: block.dateText, editNote: block.editNote,
                quotedByCount: block.quotedByCount, content: content, quotes: ReaderMessage.quotes(of: content)
            ))
        }
        let page = ReaderPage(
            topicID: topic, title: title, currentPage: max(batch.endPage, 1), maxPage: max(batch.maxPage, batch.endPage, 1),
            messages: messages
        )
        return FilteredPostsResult(
            topic: topic, page: page, startPage: batch.startPage, endPage: batch.endPage, maxPage: page.maxPage,
            isFinished: batch.isFinished
        )
    }

    private static func topicID(of target: ReaderTarget) -> TopicID? {
        if case .topic(let id) = target.source { return id }
        return nil
    }

    /// French text of a failure (legacy alert "Filtre impossible").
    nonisolated static func message(for error: FilteredPostsError) -> String {
        switch error {
        case .invalidTopic: "Ce sujet ne peut pas être filtré."
        case .network(.offline): "Pas de connexion. Réessayez une fois connecté."
        case .network(.timedOut): "Le forum n'a pas répondu à temps."
        case .network(.httpStatus(let code, _)): "Le forum a répondu avec une erreur (\(code))."
        case .network: "Une page n'a pas pu être lue."
        case .unexpectedPage, .page: "Une page du sujet est illisible."
        }
    }
}
