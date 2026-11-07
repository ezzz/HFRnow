import CoreGraphics
@testable import SwiftHFR
import Testing

/// LOT-186: the reader's bottom bar (legacy ‹ › and page menu, #428) and the scroll math with the page under the bars.
@MainActor
struct ReaderChromeTests {
    @Test func aPositionIsTheContentAtTheBarsEdge() {
        #expect(ReaderScrollGeometry.readingTop(offsetY: 400, obscuredTop: 100) == 500)
        #expect(ReaderScrollGeometry.offsetY(readingTop: 500, obscuredTop: 160) == 340)
        // The top of the page sits right under the bar, never below it with a gap.
        #expect(ReaderScrollGeometry.offsetY(readingTop: 0, obscuredTop: 100) == -100)
        #expect(ReaderScrollGeometry.offsetY(readingTop: 30, obscuredTop: 100) == -70)
        #expect(ReaderScrollGeometry.offsetY(readingTop: -40, obscuredTop: 100) == -100)
    }

    @Test func aBannerShownOrHiddenKeepsTheMessageAtTheBarsEdge() {
        // Reading at content 500 under a 100-point bar; a 60-point banner appears, then goes away.
        #expect(ReaderScrollGeometry.offsetY(keeping: 400, from: 100, to: 160) == 340)
        #expect(ReaderScrollGeometry.offsetY(keeping: 340, from: 160, to: 100) == 400)
        // At the top of the page: still at the top, under the new bars.
        #expect(ReaderScrollGeometry.offsetY(keeping: -100, from: 100, to: 160) == -160)
        #expect(ReaderScrollGeometry.offsetY(keeping: -160, from: 160, to: 100) == -100)
        // The first layout: from no inset to the bars.
        #expect(ReaderScrollGeometry.offsetY(keeping: 0, from: 0, to: 100) == -100)
    }

    @Test func thePageMenuOffersTheLastThreePagesAfterPageOne() {
        #expect(ReaderPageMenu.finalTargets(maxPage: 1).isEmpty)
        #expect(ReaderPageMenu.finalTargets(maxPage: 2) == [2])
        #expect(ReaderPageMenu.finalTargets(maxPage: 3) == [2, 3])
        #expect(ReaderPageMenu.finalTargets(maxPage: 4) == [2, 3, 4])
        #expect(ReaderPageMenu.finalTargets(maxPage: 5) == [3, 4, 5])
        #expect(ReaderPageMenu.finalTargets(maxPage: 1200) == [1198, 1199, 1200])
    }

    /// Legacy `pageChoiceMenuFinalTargets` (`MessagesView.swift:4206-4213` @ 2440d79), restated literally as the oracle.
    private func legacyFinalTargets(_ maxPage: Int) -> [Int] {
        guard maxPage > 1 else { return [] }
        var seen: Set<Int> = [1]
        return [maxPage - 2, maxPage - 1, maxPage].compactMap { target in
            guard (2...maxPage).contains(target), seen.insert(target).inserted else { return nil }
            return target
        }
    }

    @Test func thePageMenuItemsFollowLegacyOrderAndAppearOnlyPastOnePage() {
        #expect(ReaderPageMenu.items(maxPage: 1).isEmpty)
        for maxPage in [2, 40] {
            // "Dernière page" replaces legacy's last "Page N", which is the only target dropped.
            let expected: [ReaderPageMenu.Item] =
                [.first, .ask] + legacyFinalTargets(maxPage).dropLast().map(ReaderPageMenu.Item.page) + [.last, .lastPost]
            #expect(ReaderPageMenu.items(maxPage: maxPage) == expected)
        }
        #expect(ReaderPageMenu.items(maxPage: 2).map(\.title)
            == ["Première page", "Aller à la page…", "Dernière page", "Dernier post"])
        #expect(ReaderPageMenu.items(maxPage: 40).map(\.title)
            == ["Première page", "Aller à la page…", "Page 38", "Page 39", "Dernière page", "Dernier post"])
    }

    @Test func theMenuActionsOpenTheRightPageAndAnchor() {
        func go(_ item: ReaderPageMenu.Item) -> [Int]? {
            ReaderPageMenu.destination(of: item, maxPage: 40).map { [$0.page, $0.atLastMessage ? 1 : 0] }
        }
        #expect(go(.first) == [1, 0])
        #expect(go(.ask) == nil)
        #expect(go(.page(39)) == [39, 0])
        #expect(go(.last) == [40, 0])
        #expect(go(.lastPost) == [40, 1])
    }

    /// Legacy ‹ opens the previous page at its last message, › the next one at its top, "Dernier post" the last page at its
    /// last message (`MessagesView.swift:4168-4178, 4234-4236` @ 2440d79).
    @Test func previousPageAndLastPostOpenAtTheLastMessageNextPageAtTheTop() async {
        let pages = FakeTopicPages()
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic), page: 3), title: "Sujet", source: pages)
        await reader.onAppear()
        await reader.goToPage(2, atLastMessage: true)
        #expect(reader.page?.currentPage == 2)
        #expect(reader.document?.anchor == 201)
        await reader.goToPage(3)
        #expect(reader.document?.anchor == nil)
        await reader.goToPage(5, atLastMessage: true)
        #expect(reader.document?.anchor == 501)
        #expect(pages.requests.map(\.page) == [3, 2, 3, 5])
        // "Réessayer" after a failed ‹ asks again for the last message.
        pages.handler = { (_) async throws(ListLoadError) -> ReaderPage in throw .offline }
        await reader.goToPage(4, atLastMessage: true)
        #expect(reader.error == .offline)
        pages.handler = { target in readerPage(page: target.page) }
        await reader.retry()
        #expect(reader.page?.currentPage == 4)
        #expect(reader.document?.anchor == 401)
    }
}
