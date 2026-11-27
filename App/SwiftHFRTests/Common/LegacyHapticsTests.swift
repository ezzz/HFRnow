import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// #1310: the light impacts legacy plays on the Favoris empty state, on search results and on the reader's « Actualiser »
/// (`Favorites.swift:623-629`, `ForumSearchView.swift:92`, `MessagesView.swift:5051-5053, 5153-5157` @ 87fe0d1c), all through
/// `HapticFeedback` so « Retours haptiques » governs them.
@MainActor
struct LegacyHapticsTests {
    final class Recorder {
        var played: [HapticFeedback.Kind] = []
    }

    let light = HapticFeedback.Kind.impact(.light)

    func haptics(enabled: Bool = true, _ recorder: Recorder) -> HapticFeedback {
        HapticFeedback(store: InMemorySettingsStore(["haptics": .bool(enabled)])) { recorder.played.append($0) }
    }

    // MARK: Favoris empty state

    @Test func showCollapsedSectionsPlaysOneLightImpactAndTurnsTheOptionOn() {
        let recorder = Recorder()
        let options = FavoritesOptionsModel(settings: InMemorySettingsStore(), haptics: haptics(recorder))
        options.showCollapsedSectionsFromEmptyState()
        #expect(options.showsCollapsedSections)
        #expect(recorder.played == [light])
    }

    @Test func expandAllPlaysOneLightImpact() async {
        let recorder = Recorder()
        let options = FavoritesOptionsModel(settings: InMemorySettingsStore(), haptics: haptics(recorder))
        await options.expandAllFromEmptyState()
        #expect(recorder.played == [light])
    }

    @Test func theMenuTogglesStaySilent() async {
        let recorder = Recorder()
        let options = FavoritesOptionsModel(settings: InMemorySettingsStore(), haptics: haptics(recorder))
        options.showsCollapsedSections = true
        await options.expandAll()
        #expect(recorder.played.isEmpty)
    }

    @Test func theFavorisButtonsAreSilentWithHapticsOff() async {
        let recorder = Recorder()
        let options = FavoritesOptionsModel(settings: InMemorySettingsStore(), haptics: haptics(enabled: false, recorder))
        options.showCollapsedSectionsFromEmptyState()
        await options.expandAllFromEmptyState()
        #expect(options.showsCollapsedSections)
        #expect(recorder.played.isEmpty)
    }
}

// Out of the struct body, for SwiftLint's `type_body_length`.
extension LegacyHapticsTests {
    // MARK: Search results

    private func search(_ source: FakeSearchSource, _ recorder: Recorder, enabled: Bool = true) -> ForumSearchModel {
        let model = ForumSearchModel(source: source, haptics: haptics(enabled: enabled, recorder))
        model.text = "pâtes"
        return model
    }

    @Test func resultsArrivingPlayOneLightImpactPerPage() async {
        let recorder = Recorder()
        let model = search(FakeSearchSource(), recorder)
        await model.search()
        #expect(recorder.played == [light])
        await model.goToNextPage()
        #expect(recorder.played == [light, light], "a results page arriving is results arriving (legacy fetchPage)")
    }

    @Test func anEmptyAnswerStillPlaysOneImpact() async {
        let source = FakeSearchSource()
        source.searchHandler = { _ in TopicListPage(topics: [], navigation: PageNavigation(current: 1, last: 1)) }
        let recorder = Recorder()
        let model = search(source, recorder)
        await model.search()
        #expect(model.loader.value?.topics.isEmpty == true)
        #expect(recorder.played == [light], "legacy plays on every success, \"Aucun résultat\" included")
    }

    @Test func aFailedSearchPlaysNothing() async {
        let source = FakeSearchSource()
        source.searchHandler = { _ throws(ListLoadError) in throw .offline }
        let recorder = Recorder()
        let model = search(source, recorder)
        await model.search()
        #expect(model.loader.error != nil)
        #expect(recorder.played.isEmpty)
    }

    @Test func aRefusedQueryPlaysNothing() async {
        let recorder = Recorder()
        let model = search(FakeSearchSource(), recorder)
        model.text = "   "
        await model.search()
        #expect(recorder.played.isEmpty)
    }

    @Test func searchResultsAreSilentWithHapticsOff() async {
        let recorder = Recorder()
        let model = search(FakeSearchSource(), recorder, enabled: false)
        await model.search()
        await model.goToNextPage()
        #expect(model.loader.value != nil)
        #expect(recorder.played.isEmpty)
    }

    // MARK: Reader « Actualiser »

    private func shownReader(_ pages: FakeTopicPages) async -> TopicReaderModel {
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic), page: 2), title: "Sujet", source: pages)
        await reader.onAppear()
        return reader
    }

    @Test func aRefreshPlaysOneImpactAtStartAndOneAtCompletion() async {
        let pages = FakeTopicPages()
        let reader = await shownReader(pages)
        let before = pages.requests.count
        let recorder = Recorder()
        let hap = haptics(recorder)
        await ReaderRefresh.run(model: reader, controller: nil) { hap.impact(.light) }
        #expect(pages.requests.count == before + 1)
        #expect(recorder.played == [light, light])
    }

    @Test func theStartImpactComesBeforeTheRequestAndTheEndOneAfterIt() async {
        let pages = FakeTopicPages()
        let reader = await shownReader(pages)
        var seenAtPlay: [Int] = []
        let before = pages.requests.count
        await ReaderRefresh.run(model: reader, controller: nil) { seenAtPlay.append(pages.requests.count - before) }
        #expect(seenAtPlay == [0, 1])
    }

    @Test func aFailedRefreshStillPlaysTheCompletionImpact() async {
        let pages = FakeTopicPages()
        let reader = await shownReader(pages)
        pages.handler = { _ throws(ListLoadError) in throw .offline }
        let recorder = Recorder()
        let hap = haptics(recorder)
        await ReaderRefresh.run(model: reader, controller: nil) { hap.impact(.light) }
        #expect(reader.error != nil)
        #expect(recorder.played == [light, light], "legacy finishes the haptic on failure too (MessagesView.swift:3793)")
    }

    /// A refresh the model refuses (a composer is open) sends nothing, so it plays nothing either.
    @Test func aRefreshRefusedUnderAnOpenComposerPlaysNothingAndSendsNothing() async {
        let pages = FakeTopicPages()
        let reader = await shownReader(pages)
        reader.composer(.reply, isOpen: true)
        let before = pages.requests.count
        let recorder = Recorder()
        let hap = haptics(recorder)
        await ReaderRefresh.run(model: reader, controller: nil) { hap.impact(.light) }
        #expect(pages.requests.count == before)
        #expect(recorder.played.isEmpty)
    }

    @Test func aRefreshIsSilentWithHapticsOff() async {
        let reader = await shownReader(FakeTopicPages())
        let recorder = Recorder()
        let hap = haptics(enabled: false, recorder)
        await ReaderRefresh.run(model: reader, controller: nil) { hap.impact(.light) }
        #expect(recorder.played.isEmpty)
    }
}
