import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRStorage
import Observation

/// A forum the search can be limited to.
struct SearchCategory: Identifiable, Hashable, Sendable {
    let id: CategoryID
    let title: String
}

/// How far back the search goes (legacy `ForumSearchParams.DateRange`, `ForumSearchService.swift:49-76`).
enum SearchPeriod: CaseIterable, Hashable, Sendable {
    case fromBeginning, fiveYears, oneYear

    var title: String {
        switch self {
        case .fromBeginning: "Début"
        case .fiveYears: "5 ans"
        case .oneYear: "1 an"
        }
    }

    /// Years back from today, nil from the beginning.
    var yearOffset: Int? {
        switch self {
        case .fromBeginning: nil
        case .fiveYears: -5
        case .oneYear: -1
        }
    }
}

/// One results page ready to display.
struct SearchContent: Sendable, Equatable {
    var topics: [TopicSummary]
    var page: Int
    var firstPath: String?
    var previousPath: String?
    var nextPath: String?
    /// HFR's sentence when nothing matched.
    var notice: String?

    init(page list: TopicListPage) {
        topics = list.topics
        page = list.navigation.current
        firstPath = list.navigation.firstPath
        previousPath = list.navigation.previousPath
        nextPath = list.navigation.nextPath
        notice = list.notice
    }
}

/// State of the forum search screen (LOT-115): the form, the results page on screen, the result opened in the reader.
///
/// A banned word (Q-7) is refused here, before any request, with a warning. Results keep their rows while another page
/// loads or fails (`ContentLoader`).
@MainActor
@Observable
final class ForumSearchModel {
    var text = ""
    /// Forum searched; the last choice is kept (`recherche_categorie`, default 13 Discussions, as legacy).
    var category: CategoryID {
        didSet { if category != oldValue { store?.set(category, for: SettingKey.searchCategory) } }
    }
    var matchMode = GlobalSearchQuery.MatchMode.allWords
    var scope = GlobalSearchQuery.Scope.titleAndContent
    var period = SearchPeriod.fromBeginning
    /// Forums offered by the picker, from the forum list (Apple category already filtered, Q-7).
    private(set) var categories: [SearchCategory] = []
    /// The banned word the last submit was refused for; cleared by the next accepted search.
    private(set) var bannedWord: String?
    /// A search was submitted (accepted), so an empty result is "no result" and not a blank form.
    private(set) var hasSearched = false
    let loader = ContentLoader<SearchContent>()
    /// Result chosen in the list, shown by the reader.
    var selected: TopicSummary? {
        didSet { if selected == nil { currentReader = nil } }
    }

    private let source: any ForumSearchSource
    private let store: (any SettingsStore)?
    private let topicPages: any TopicPageSource
    private let renderOptions: @Sendable () -> ReaderRenderOptions
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    /// Pager path of the last page asked for, for a retry; nil when it was the first page.
    @ObservationIgnored private var requestedPath: String?
    @ObservationIgnored private var currentReader: (id: String, model: TopicReaderModel)?

    /// Creates the model over `source`.
    init(
        source: any ForumSearchSource,
        topicPages: any TopicPageSource = UnavailableTopicPages(),
        renderOptions: @escaping @Sendable () -> ReaderRenderOptions = { ReaderRenderOptions() },
        store: (any SettingsStore)? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.store = store
        category = store?.value(for: SettingKey.searchCategory) ?? .forum(13)
        self.source = source
        self.topicPages = topicPages
        self.renderOptions = renderOptions
        self.now = now
        self.calendar = calendar
    }

    /// Takes the forums of the home page, keeping the chosen one when it is still offered (else Discussions, the legacy default).
    func setCategories(from content: ForumListContent?) {
        let list: [SearchCategory] = (content?.sections ?? []).compactMap { section in
            guard case .forum(let id, _)? = section.rows.first?.source else { return nil }
            return SearchCategory(id: id, title: section.title)
        }
        categories = list
        if !list.isEmpty, !list.contains(where: { $0.id == category }) {
            category = list.first { $0.id == .forum(13) }?.id ?? list[0].id
        }
    }

    var canSubmit: Bool { !trimmedText.isEmpty && !loader.isLoading }

    /// Words of 1 to 3 letters: HFR may not index them (HFR-PROTOCOL §7 "Search", unsettled), so the form only hints.
    var hasShortWord: Bool {
        trimmedText.split(whereSeparator: \.isWhitespace).contains { $0.count < 4 }
    }

    var canGoToNext: Bool { loader.value?.nextPath != nil && !loader.isLoading }
    var canGoToPrevious: Bool { loader.value?.previousPath != nil && !loader.isLoading }

    /// Submits the form: refuses a banned word without sending anything, else loads the first results page.
    func search() async {
        let words = trimmedText
        guard !words.isEmpty, !loader.isLoading else { return }
        if let word = GlobalSearchFlow.bannedWords.first(where: { words.lowercased().contains($0) }) {
            bannedWord = word
            return
        }
        bannedWord = nil
        hasSearched = true
        selected = nil
        requestedPath = nil
        let query = GlobalSearchQuery(text: words, category: category, matchMode: matchMode, scope: scope, dateRange: dateRange())
        let source = source
        await loader.load { () async throws(ListLoadError) -> SearchContent in
            SearchContent(page: try await source.search(query))
        }
    }

    func goToNextPage() async { if canGoToNext, let path = loader.value?.nextPath { await load(path: path) } }
    func goToPreviousPage() async { if canGoToPrevious, let path = loader.value?.previousPath { await load(path: path) } }
    func goToFirstPage() async { if canGoToPrevious, let path = loader.value?.firstPath { await load(path: path) } }

    /// Asks again for what failed: the page asked for, or the whole search.
    func retry() async {
        if let path = requestedPath { await load(path: path) } else { await search() }
    }

    /// Stops the search in flight (leaving the screen, Annuler).
    func cancel() { loader.cancel() }

    /// The reader of `topic`, opened at the matching message; the same model while the result stays selected.
    func reader(for topic: TopicSummary) -> TopicReaderModel? {
        if let currentReader, currentReader.id == topic.id { return currentReader.model }
        guard let target = Self.target(of: topic) else { return nil }
        let model = TopicReaderModel(target: target, title: topic.title, source: topicPages, renderOptions: renderOptions)
        currentReader = (topic.id, model)
        return model
    }

    /// The matching message when the row names one, else what a topic row opens.
    static func target(of topic: TopicSummary) -> ReaderTarget? {
        if let hit = topic.searchHit, let target = ReaderTarget(link: hit.postPath, fallbackTopic: topic.topicID) { return target }
        return ReaderTarget(opening: topic)
    }

    /// Start date of the period (legacy `legacyDictionary`, `ForumSearchService.swift:104-127`).
    func dateRange() -> GlobalSearchQuery.DateRange {
        guard let offset = period.yearOffset, let date = calendar.date(byAdding: .year, value: offset, to: now()) else {
            return .fromBeginning
        }
        let parts = calendar.dateComponents([.day, .month, .year], from: date)
        return .since(day: parts.day ?? 1, month: parts.month ?? 1, year: parts.year ?? 2000)
    }

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func load(path: String) async {
        requestedPath = path
        selected = nil
        let source = source
        await loader.load { () async throws(ListLoadError) -> SearchContent in
            SearchContent(page: try await source.page(atPath: path))
        }
    }
}
