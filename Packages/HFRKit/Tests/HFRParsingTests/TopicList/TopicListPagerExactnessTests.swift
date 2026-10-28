import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// Whether a list pager's last page is the page count or a lower bound (LOT-167), on the LOT-001 captures.
@Suite("Topic list pager exactness")
struct TopicListPagerExactnessTests {
    @Test("Windowed pagers are a lower bound (LOT-167)", arguments: [
        ("R04-list-cat13-p1-anon", "/hfr/Discussions/liste_sujet-1.htm"),
        ("R05a-list-cat13-p12-anon", "/hfr/Discussions/liste_sujet-12.htm"),
        ("R05b-list-cat13-p500-anon", "/hfr/Discussions/liste_sujet-500.htm")
    ])
    func windowedPagerIsLowerBound(capture: String, path: String) throws {
        let page = try TopicListParser.parse(Fixture.capture(capture), pageURL: path)
        #expect(page.navigation.isExact == false)
    }

    @Test("A short contiguous pager is the exact page count (LOT-167)", arguments: [
        ("R08-2-list-cat13-owntopic2", "/forum1f.php?owntopic=2", 1),
        ("R50b-search-results-no-cookie", "/search.php", 2)
    ])
    func shortPagerIsExact(capture: String, path: String, pages: Int) throws {
        let page = try TopicListParser.parse(Fixture.capture(capture), pageURL: path)
        #expect(page.navigation.last == pages)
        #expect(page.navigation.isExact)
    }

    @Test("A topic row's page count is exact while the pager's last page is not (LOT-167, B1)")
    func rowCountBeatsThePagerWindow() throws {
        let page = try TopicListParser.parse(Fixture.capture("R04-list-cat13-p1-anon"), pageURL: "/hfr/Discussions/liste_sujet-1.htm")
        #expect(page.navigation.last == 500)
        #expect(page.navigation.isExact == false)
        // Oracle R04: the first row has 84 pages (`sujetCase4`); row 8 has 35634, far past the pager's last link.
        #expect(page.topics.first?.pageCount == 84)
        #expect(page.topics.map(\.pageCount).max() ?? 0 > page.navigation.last)
    }

    @Test("Pager shapes: only 1…N below the window size is exact (LOT-167)")
    func exactnessRule() {
        #expect(TopicListPager.isExactCount(of: [1]))
        #expect(TopicListPager.isExactCount(of: [1, 2, 3, 4, 5, 6, 7, 8, 9]))
        #expect(!TopicListPager.isExactCount(of: Array(1...10)))
        #expect(!TopicListPager.isExactCount(of: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30]))
        #expect(!TopicListPager.isExactCount(of: [1, 10, 11, 12]))
        #expect(!TopicListPager.isExactCount(of: [2, 3]))
        #expect(!TopicListPager.isExactCount(of: []))
    }
}
