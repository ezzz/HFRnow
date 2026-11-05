import HFRClient
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

@MainActor @Suite(.timeLimit(.minutes(1)))
struct FilteredPostsEntryTests {
    private func model(_ source: FakeFilteredSource) -> FilteredPostsModel {
        FilteredPostsModel(
            services: FilteredPostsServices(source: source, criteria: { FilteredPostsCriteria() }, normalizer: LiveContentNormalizer())
        )
    }

    private func settle(_ model: FilteredPostsModel) async {
        while model.isRunning || model.isAdvancing { await Task.yield() }
    }

    @Test func aFavouriteStartsAtItsResumePageAfterItsLastReadMessage() async {
        let source = FakeFilteredSource { page, _, _ in filteredBatch(start: page, end: page) }
        let model = model(source)
        let row = TopicSummary(
            topicID: filterTopic, title: "Sujet", path: "/forum2.php?config=hfr.inc&cat=13&post=28563&page=1",
            flagPath: "/forum2.php?config=hfr.inc&cat=13&post=28563&page=7#t4321", currentPage: 7
        )
        model.start(opening: row)
        await settle(model)
        #expect(source.calls.map(\.page) == [7])
        #expect(source.calls.map(\.after) == [4321])
        #expect(source.calls.map(\.topic) == [filterTopic])
    }

    @Test func aRowWithoutAResumeLinkStartsAtItsOwnPage() async {
        let source = FakeFilteredSource { page, _, _ in filteredBatch(start: page, end: page) }
        let model = model(source)
        let row = TopicSummary(topicID: filterTopic, title: "Sujet", path: "/forum2.php?config=hfr.inc&cat=13&post=28563&page=3")
        model.start(opening: row)
        await settle(model)
        #expect(source.calls.map(\.page) == [3])
        #expect(source.calls.map(\.after) == [nil])
    }

    @Test func aMessageLinkStartsAtTheRowsPageNotThePlaceholder() async {
        let source = FakeFilteredSource { page, _, _ in filteredBatch(start: page, end: page) }
        let model = model(source)
        let row = TopicSummary(
            topicID: filterTopic, title: "Sujet", path: "/x",
            flagPath: "/forum2.php?config=hfr.inc&cat=13&post=28563&numreponse=999#t999", currentPage: 6
        )
        model.start(opening: row)
        await settle(model)
        #expect(source.calls.map(\.page) == [6])
        #expect(source.calls.map(\.after) == [999])
    }

    @Test func aRowThatNamesNoTopicShowsAnErrorAndRequestsNothing() {
        let source = FakeFilteredSource { page, _, _ in filteredBatch(start: page, end: page) }
        let model = model(source)
        model.start(opening: TopicSummary(title: "Rien", path: "/rien"))
        #expect(model.errorMessage == "Ce sujet ne peut pas être filtré.")
        #expect(source.calls.isEmpty)
        #expect(!model.isRunning)
    }

    @Test func theCriteriaComeFromTheSettings() {
        let store = InMemorySettingsStore([
            "filter_posts_min_quotes": .int(7), "filter_posts_quotes": .string("pseudo")
        ])
        let criteria = FilteredPostsServices.criteria(store: store, pseudo: "moi", allowlist: ["ami"])
        #expect(criteria == FilteredPostsCriteria(minimumQuoteCount: 7, pseudo: "moi", allowlist: ["ami"], includesAllowlist: false))
        let defaults = FilteredPostsServices.criteria(store: InMemorySettingsStore(), pseudo: nil, allowlist: [])
        #expect(defaults == FilteredPostsCriteria(minimumQuoteCount: 3, pseudo: nil, allowlist: [], includesAllowlist: true))
    }

    @Test func theFilterSettingsAreShownAndWrittenInLegacyShape() {
        let store = InMemorySettingsStore(["filter_posts_min_quotes": .int(6)])
        let model = GeneralSettingsModel(store: store)
        #expect(model.filterMinimumQuotes == 6)
        #expect(model.filterMinimumQuoteOptions == [3, 4, 5, 6, 7, 10])
        #expect(model.filterIncludesAllowlist)
        model.filterMinimumQuotes = 10
        model.filterIncludesAllowlist = false
        #expect(store.rawValue(forKey: "filter_posts_min_quotes") == .int(10))
        #expect(store.rawValue(forKey: "filter_posts_quotes") == .string("pseudo"))
        model.filterIncludesAllowlist = true
        #expect(store.rawValue(forKey: "filter_posts_quotes") == .string("wl_pseudo"))
        #expect(GeneralSettingsModel(store: InMemorySettingsStore()).filterMinimumQuoteOptions == [3, 4, 5, 7, 10])
    }
}
