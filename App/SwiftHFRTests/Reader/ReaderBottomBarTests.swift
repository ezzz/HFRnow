import HFRNetwork
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// Issues #820 and #649: the reader's bottom bar at the end of a page (legacy `shouldShowBottomRefreshButton` and
/// `shouldPromoteBottomNextPageButton`, `MessagesView.swift:4972-4978` @ 87fe0d1c), its place beside a visible tab bar, the
/// pull past the end, and the one refresh behind every "Actualiser". Topic and private conversation share this bar.
@MainActor
struct ReaderBottomBarTests {
    private typealias State = ReaderBottomBar.State

    @Test func midPageTheBarShowsOnlyTheArrows() {
        let mid = ReaderBottomBar.state(currentPage: 3, maxPage: 5, atPageEnd: false, voiceOver: false)
        #expect(mid == State(showsPageBubble: false, showsRefresh: false, canGoPrevious: true, canGoNext: true))
        #expect(mid.centre.isEmpty && mid.trailing == [.reply])
    }

    @Test func atTheEndOfAPageTheBubbleAndTheRefreshAppear() {
        #expect(ReaderBottomBar.state(currentPage: 3, maxPage: 5, atPageEnd: true, voiceOver: false)
            == State(showsPageBubble: true, showsRefresh: true, canGoPrevious: true, canGoNext: true))
    }

    /// Issue #965: ‹ is greyed and disabled on the first page, › on the last, mid-page and at the end of the page alike; elsewhere
    /// both carry the accent. No pill is filled with the accent any more (no "promoted" state exists).
    @Test(arguments: [false, true])
    func theArrowsAreGreyedAtTheFirstAndLastPage(atPageEnd: Bool) {
        func state(_ page: Int, of max: Int) -> State {
            ReaderBottomBar.state(currentPage: page, maxPage: max, atPageEnd: atPageEnd, voiceOver: false)
        }
        let first = state(1, of: 5)
        #expect(!first.canGoPrevious && first.canGoNext)
        #expect(first.previousTint == .grey && first.nextTint == .accent)
        let middle = state(3, of: 5)
        #expect(middle.canGoPrevious && middle.canGoNext)
        #expect(middle.previousTint == .accent && middle.nextTint == .accent)
        let last = state(5, of: 5)
        #expect(last.canGoPrevious && !last.canGoNext)
        #expect(last.previousTint == .accent && last.nextTint == .grey)
        // A one-page topic has nowhere to go.
        let only = state(1, of: 1)
        #expect(only.previousTint == .grey && only.nextTint == .grey)
    }

    /// Hiding the bubble is visual only: VoiceOver keeps the page menu anywhere on the page.
    @Test func voiceOverKeepsThePageBubbleMidPage() {
        let state = ReaderBottomBar.state(currentPage: 3, maxPage: 5, atPageEnd: false, voiceOver: true)
        #expect(state.showsPageBubble)
        #expect(!state.showsRefresh)
    }

    /// Issue #961: the "N / M" bubble is its own pill between ‹ › (left) and refresh + reply (right).
    @Test func thePageBubbleIsItsOwnCentredPill() {
        let end = ReaderBottomBar.state(currentPage: 3, maxPage: 5, atPageEnd: true, voiceOver: false)
        #expect(end.leading == [.previous, .next] && end.separatesArrows, "‹ and › are two pills at the end of the page (#965)")
        #expect(!ReaderBottomBar.state(currentPage: 3, maxPage: 5, atPageEnd: false, voiceOver: true).separatesArrows)
        #expect(end.centre == [.pageBubble])
        #expect(end.trailing == [.refresh, .reply])
        #expect(!end.trailing.contains(.pageBubble) && !end.leading.contains(.pageBubble))
        // VoiceOver mid-page: the same layout, the bubble still apart, with the reply alone on the right.
        let voiceOver = ReaderBottomBar.state(currentPage: 3, maxPage: 5, atPageEnd: false, voiceOver: true)
        #expect(voiceOver.centre == [.pageBubble])
        #expect(voiceOver.trailing == [.reply])
        // Mid-page without VoiceOver and without a reply button: arrows only.
        let mid = ReaderBottomBar.state(currentPage: 3, maxPage: 5, atPageEnd: false, voiceOver: false, showsReply: false)
        #expect(mid.centre.isEmpty && mid.trailing.isEmpty)
    }

    /// Issue #649: a Pro Max in landscape is regular width with the tab bar shown: the system bottom bar would sit under it.
    @Test func besideAVisibleTabBarTheControlsAreAStripAboveIt() {
        func placement(root tabBar: Bool, _ sizeClass: UserInterfaceSizeClass, selected: Bool = true) -> ReaderBottomBar.Placement {
            ReaderBottomBar.placement(
                rootHasTabBar: tabBar, tabBar: ReaderTabBar.visibility(sizeClass: sizeClass, isSelectedTab: selected)
            )
        }
        #expect(placement(root: true, .regular) == .inset)
        // Compact width hides the tab bar while the reader is open: the system bottom bar is free.
        #expect(placement(root: true, .compact) == .bottomBar)
        // The iPad sidebar root has no tab bar.
        #expect(placement(root: false, .regular) == .bottomBar)
        #expect(placement(root: false, .compact) == .bottomBar)
    }

    @Test func aPullCountsFromTheContentsEndAboveTheBottomBars() {
        // 1000 points of content, 800 of screen, 100 of bars on top and 50 below: the last offset is 250.
        #expect(ReaderScrollGeometry.pastEnd(offsetY: 250, viewportHeight: 800, contentHeight: 1000, insetTop: 100, insetBottom: 50) == 0)
        #expect(ReaderScrollGeometry.pastEnd(offsetY: 330, viewportHeight: 800, contentHeight: 1000, insetTop: 100, insetBottom: 50) == 80)
        #expect(ReaderScrollGeometry.pastEnd(offsetY: 0, viewportHeight: 800, contentHeight: 1000, insetTop: 100, insetBottom: 50) < 0)
        // A page shorter than the screen ends at its top: the pull counts from there.
        #expect(ReaderScrollGeometry.pastEnd(offsetY: -28, viewportHeight: 800, contentHeight: 300, insetTop: 100, insetBottom: 50) == 72)
    }

    @Test func onlyAPullBeyondTheThresholdRefreshes() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset = UIEdgeInsets(top: 100, left: 0, bottom: 50, right: 0)
        scrollView.contentSize = CGSize(width: 390, height: 1000)
        scrollView.contentOffset = CGPoint(x: 0, y: 250 + ReaderPullWatcher.threshold - 1)
        #expect(!ReaderPullWatcher.isPulledPastEnd(scrollView))
        scrollView.contentOffset = CGPoint(x: 0, y: 250 + ReaderPullWatcher.threshold)
        #expect(ReaderPullWatcher.isPulledPastEnd(scrollView))
        // At the end of the page, but not pulled: nothing.
        scrollView.contentOffset = CGPoint(x: 0, y: 250)
        #expect(!ReaderPullWatcher.isPulledPastEnd(scrollView))
    }

    /// A pan gesture already let go: what UIKit hands the watcher at the end of a drag.
    private final class ReleasedPan: UIPanGestureRecognizer {
        override var state: UIGestureRecognizer.State {
            get { .ended }
            set {}
        }
    }

    @MainActor
    private final class Pulls {
        var times = 0
    }

    /// The watcher's gesture action: a release beyond the threshold reports a pull, a shorter one or a drag still under way does not.
    @Test func theWatcherReportsAPullOnlyWhenTheDragEndsBeyondTheThreshold() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentSize = CGSize(width: 390, height: 1000)
        let pulls = Pulls()
        let watcher = ReaderPullWatcher()
        watcher.track(scrollView) { pulls.times += 1 }
        scrollView.contentOffset = CGPoint(x: 0, y: 200 + ReaderPullWatcher.threshold - 1)
        watcher.panned(ReleasedPan())
        #expect(pulls.times == 0)
        scrollView.contentOffset = CGPoint(x: 0, y: 200 + ReaderPullWatcher.threshold)
        watcher.panned(UIPanGestureRecognizer())
        #expect(pulls.times == 0, "a drag that has not ended does not refresh")
        watcher.panned(ReleasedPan())
        #expect(pulls.times == 1)
    }

    /// Only the topic and MP reader refreshes on a pull: its pages carry the hint, "Filtrer les posts" builds without it.
    @Test func onlyTheReadersPagesOfferThePull() async {
        #expect(!ReaderRenderOptions().offersPullToRefresh)
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic), page: 1), source: FakeTopicPages())
        #expect(reader.currentRenderOptions().offersPullToRefresh)
        await reader.onAppear()
        #expect(reader.document?.html.contains("class=\"pull-hint\"") == true)
    }

    @MainActor
    private final class Box {
        var atPageEnd = false
        var played: [HapticFeedback.Kind] = []
    }

    private struct Wired {
        let reader: TopicReaderModel
        let controller: ReaderWebController
        let pages: FakeTopicPages
        let box: Box
        let token: Int
    }

    private func wired() async throws -> Wired {
        let pages = FakeTopicPages()
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic), page: 2), title: "Sujet", source: pages)
        await reader.onAppear()
        let controller = ReaderWebController(
            imageFetcher: ReaderImageFetcher(transport: MockTransport(replies: [])),
            autoLoadsThirdPartyImages: { false }
        )
        let box = Box()
        let binding = Binding(get: { box.atPageEnd }, set: { box.atPageEnd = $0 })
        ReaderRefresh.wirePageEnd(of: controller, model: reader, atPageEnd: binding) { box.played.append(.impact(.light)) }
        return Wired(reader: reader, controller: controller, pages: pages, box: box, token: try #require(reader.document?.token))
    }

    @Test func thePageEndFollowsTheShownDocumentOnly() async throws {
        let setup = try await wired()
        let (controller, box, token) = (setup.controller, setup.box, setup.token)
        controller.events.pageEnd(true, token + 1)
        #expect(!box.atPageEnd, "a late report of another document changes nothing")
        controller.events.pageEnd(true, token)
        #expect(box.atPageEnd)
        controller.events.pageEnd(false, token)
        #expect(!box.atPageEnd)
    }

    /// A pull past the end plays legacy's light impact and reloads the page on screen, keeping the position, as "Actualiser".
    @Test func aPullPastTheEndRefreshesThePageOnScreenWithAHaptic() async throws {
        let setup = try await wired()
        let (reader, controller, pages, box, token) = (setup.reader, setup.controller, setup.pages, setup.box, setup.token)
        let before = pages.requests.count
        controller.events.pulled(token + 1)
        #expect(box.played.isEmpty, "a pull reported for another document does nothing")
        controller.events.pulled(token)
        #expect(box.played == [.impact(.light)])
        for _ in 0..<200 where pages.requests.count == before { try await Task.sleep(for: .milliseconds(10)) }
        #expect(pages.requests.count == before + 1)
        #expect(pages.requests.last?.page == 2)
        #expect(reader.document?.keepsScrollPosition == true)
    }
}
