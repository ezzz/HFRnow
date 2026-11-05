import CoreGraphics
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// LOT-106: layout, signatures and page swipe of the reader.
@MainActor
struct ReaderDisplaySettingsTests {
    private func reader(_ store: InMemorySettingsStore, _ pages: FakeTopicPages, page: Int = 2) -> TopicReaderModel {
        let settings = ReaderSettings.live(store: store, isOnWiFi: { true })
        return TopicReaderModel(
            target: ReaderTarget(source: .topic(readerTopic), page: page), title: "Sujet", source: pages,
            renderOptions: settings.renderOptions
        )
    }

    @Test func theMessageStyleIsAClassOnTheBodyAndModernIsTheLegacyDefault() {
        let store = InMemorySettingsStore()
        let settings = ReaderSettings.live(store: store, isOnWiFi: { true })
        #expect(settings.renderOptions().style == .modern)
        store.set(ThemeStyle.classic, for: SettingKey.themeStyle)
        #expect(settings.renderOptions().style == .classic)
        let classic = TopicHTMLBuilder.document(for: readerPage(page: 1), token: 1, options: settings.renderOptions())
        #expect(classic.contains("style-classic"))
        #expect(!classic.contains("style-modern"))
        let modern = TopicHTMLBuilder.document(for: readerPage(page: 1), token: 1)
        #expect(modern.contains("style-modern"))
    }

    @Test func swipeSettingDefaultsOnAndFollowsTheStore() {
        let store = InMemorySettingsStore()
        let settings = ReaderSettings.live(store: store, isOnWiFi: { true })
        #expect(settings.swipesPages())
        store.set(false, for: SettingKey.topicPageSwipe)
        #expect(!settings.swipesPages())
    }

    @Test func aChangedSettingRebuildsTheShownPageWithoutARequest() async {
        let store = InMemorySettingsStore()
        let pages = FakeTopicPages()
        let model = reader(store, pages)
        await model.onAppear()
        let first = model.document
        model.applyDisplaySettings()
        #expect(model.document == first) // nothing changed: same document, not rebuilt
        store.set(ThemeStyle.classic, for: SettingKey.themeStyle)
        model.applyDisplaySettings()
        #expect(model.document?.token == (first?.token ?? 0) + 1)
        #expect(model.document?.html.contains("style-classic") == true)
        #expect(model.document?.keepsScrollPosition == true)
        #expect(model.document?.anchor == nil)
        #expect(pages.requests.count == 1)
        model.applyDisplaySettings()
        #expect(model.document?.token == (first?.token ?? 0) + 1) // applied once
    }

    @Test func nothingIsRebuiltBeforeAPageIsShown() {
        let store = InMemorySettingsStore()
        let model = reader(store, FakeTopicPages())
        store.set(true, for: SettingKey.displaySignatures)
        model.applyDisplaySettings()
        #expect(model.document == nil)
    }

    @Test func aSettingChangedDuringALoadThatFailsIsAppliedWhenItEnds() async {
        let store = InMemorySettingsStore()
        let pages = FakeTopicPages()
        let model = reader(store, pages)
        await model.onAppear()
        let gate = ReaderGate()
        pages.handler = { (_) async throws(ListLoadError) -> ReaderPage in await gate.wait(); throw .cancelled }
        let load = Task { await model.refresh() }
        await gate.untilArrived()
        store.set(ThemeStyle.classic, for: SettingKey.themeStyle)
        model.applyDisplaySettings() // loading: ignored
        #expect(model.document?.html.contains("style-classic") == false)
        await gate.open()
        await load.value
        #expect(model.document?.html.contains("style-classic") == true)
    }

    @Test func swipingOpensTheNextPageFromItsTopAndThePreviousFromItsEnd() async {
        let pages = FakeTopicPages { target in readerPage(page: target.page, maxPage: 5) }
        let model = reader(InMemorySettingsStore(), pages, page: 3)
        await model.onAppear()
        await model.swipe(.next) // the first document is not ready yet: a swipe on the old page is ignored
        #expect(pages.requests.map(\.page) == [3])
        model.documentDidBecomeReady(token: model.document?.token ?? 0)
        await model.swipe(.next)
        #expect(pages.requests.map(\.page) == [3, 4])
        #expect(model.document?.anchor == nil)
        model.documentDidBecomeReady(token: model.document?.token ?? 0)
        await model.swipe(.previous)
        #expect(pages.requests.map(\.page) == [3, 4, 3])
        let last = model.page?.messages.last { !$0.isContinuation }?.numreponse
        #expect(last != nil)
        #expect(model.document?.anchor == last)
    }

    @Test func swipingPastTheEndsDoesNothing() async {
        let pages = FakeTopicPages { target in readerPage(page: target.page, maxPage: 1) }
        let model = reader(InMemorySettingsStore(), pages, page: 1)
        await model.onAppear()
        model.documentDidBecomeReady(token: model.document?.token ?? 0)
        await model.swipe(.next)
        await model.swipe(.previous)
        #expect(pages.requests.count == 1)
    }

    @Test func theSwipeRuleIsTheLegacyOne() {
        func swipe(_ across: CGFloat, down: CGFloat = 0, predicted: CGFloat, page: Int = 2, max: Int = 5) -> PageSwipe? {
            PageSwipe.of(
                translation: CGSize(width: across, height: down), predictedEnd: CGSize(width: predicted, height: down),
                page: page, maxPage: max
            )
        }
        #expect(swipe(-150, predicted: -300) == .next)
        #expect(swipe(150, predicted: 300) == .previous)
        #expect(swipe(-100, predicted: -300) == nil) // under 120 pt
        #expect(swipe(-150, predicted: -200) == nil) // impulse 50 < 70
        #expect(swipe(-150, predicted: -100) == nil) // impulse against the drag
        #expect(swipe(-150, down: 90, predicted: -300) == nil) // vertical 90 >= 75
        #expect(swipe(-150, down: 70, predicted: -300) == .next)
        #expect(swipe(-150, predicted: -300, page: 5) == nil) // no next page
        #expect(swipe(150, predicted: 300, page: 1) == nil) // no previous page
        #expect(swipe(-120, predicted: -300) == nil) // exactly 120 pt is not enough (legacy `>`)
        #expect(swipe(-121, predicted: -191) == nil) // impulse exactly 70
        #expect(swipe(-121, predicted: -192) == .next)
        #expect(swipe(-200, down: 100, predicted: -400) == nil) // vertical exactly 0.5 x horizontal
    }
}
