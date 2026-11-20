import HFRModels
@testable import SwiftHFR
import Testing
import UIKit

/// The Plus tab across a fold (LOT-147): Bookmarks and Alertes Qualitay carry their topic between the split's detail column and
/// the Plus stack of the cover screen, as legacy's `handleRootSwap` (`MainWindow.swift:2157-2172` @ 87fe0d1c) and
/// `foldHandoffDestination` on the Plus root (`:1836-1839`). The hosting helpers are `DuoLayoutHostedTests`'s.
extension DuoLayoutHostedTests {
    /// A fold hands the topic a Plus list opened, on its page, to the Plus stack of the cover screen, over the list; an unfold
    /// hands it back to the detail column (legacy `requestCompactPush(tab: .more, …)`, then `selectTopic(_, for:)` on the
    /// Bookmarks / Alertes Qualitay destination).
    @Test(arguments: [PlusEntry.bookmarks, .qualityAlerts])
    func aFoldAndAnUnfoldKeepThePlusTopicAndItsPage(entry: PlusEntry) async throws {
        let hosted = try host(initial: .plus(entry))
        defer { hosted.window.isHidden = true }
        let (window, root) = (hosted.window, hosted.root)
        #expect(await settle(window) { split(in: window) != nil }, "no split root: \(stacks(in: window))")
        let open = RootSidebarView.detailOpener(model: root, environment: hosted.environment, entry: entry)
        open(ReaderTarget(source: .topic(TopicID(category: .forum(13), topic: 5))), title: "Sujet 5")
        let reader = try #require(root.detailReaders[entry])
        #expect(await settle(window) { reader.page != nil && shows("Sujet 5 p1", in: window) }, "\(stacks(in: window))")
        await reader.goToPage(3)
        #expect(await settle(window) { shows("Sujet 5 p3", in: window) }, "\(stacks(in: window))")

        fold(window, host: hosted.host)
        let folded = await settle(window) { hasTabBar(window) && shows("Sujet 5 p3", in: window) }
        #expect(folded, "\(entry) folded: tab bar \(hasTabBar(window)), \(stacks(in: window))")
        let overTheList = stacks(in: window).contains { $0.suffix(2) == [entry.title, "Sujet 5 p3"] }
        #expect(overTheList, "the topic is not over the \(entry) list: \(stacks(in: window))")
        #expect(root.detailReaders[entry] === reader, "the reader (and its page) was not kept")

        unfold(window, host: hosted.host)
        let unfolded = await settle(window) { !hasTabBar(window) && split(in: window) != nil && shows("Sujet 5 p3", in: window) }
        #expect(unfolded, "\(entry) unfolded: tab bar \(hasTabBar(window)), \(stacks(in: window))")
        #expect(root.detailReaders[entry] === reader)
    }

    /// Back on the cover screen closes the Plus topic, so an unfold shows the entry's placeholder, not the topic read before the
    /// fold (legacy `handleRootSwap`: nothing read, every split selection cleared, `MainWindow.swift:2157-2160` @ 87fe0d1c).
    @Test func aPlusTopicClosedOnTheCoverScreenDoesNotComeBackUnfolded() async throws {
        let hosted = try host(initial: .plus(.bookmarks))
        defer { hosted.window.isHidden = true }
        let (window, root) = (hosted.window, hosted.root)
        let open = RootSidebarView.detailOpener(model: root, environment: hosted.environment, entry: .bookmarks)
        open(ReaderTarget(source: .topic(TopicID(category: .forum(13), topic: 5))), title: "Sujet 5")
        #expect(await settle(window) { shows("Sujet 5 p1", in: window) }, "\(stacks(in: window))")
        fold(window, host: hosted.host)
        _ = await settle(window) { hasTabBar(window) && shows("Sujet 5 p1", in: window) }

        let stack = try #require(
            controllers(in: window).lazy.compactMap { $0 as? UINavigationController }.first {
                $0.viewControllers.last?.navigationItem.title == "Sujet 5 p1" && $0.viewControllers.count > 1
            },
            "no topic pushed on the cover screen: \(stacks(in: window))"
        )
        stack.popViewController(animated: false)
        #expect(await settle(window) { root.detailReaders[.bookmarks] == nil }, "back kept the reader: \(stacks(in: window))")

        unfold(window, host: hosted.host)
        #expect(await settle(window) { !hasTabBar(window) && split(in: window) != nil })
        try await Task.sleep(for: .milliseconds(500))
        #expect(!shows("Sujet 5 p1", in: window), "the closed topic came back: \(stacks(in: window))")
        #expect(root.detailReaders[.bookmarks] == nil)
    }

    /// A topic opened from a Plus list on the cover screen is the entry's detail reader: the cover pushes it on the Plus stack, and
    /// an unfold shows it in the detail column beside the list (legacy carries the Plus reading towards Bookmarks / Alertes
    /// Qualitay, `MainWindow.swift:2161-2172` @ 87fe0d1c).
    @Test func aPlusTopicOpenedOnTheCoverScreenShowsBesideTheListUnfolded() async throws {
        let hosted = try host(initial: .plus(.qualityAlerts))
        defer { hosted.window.isHidden = true }
        let (window, root) = (hosted.window, hosted.root)
        fold(window, host: hosted.host)
        #expect(await settle(window) { hasTabBar(window) && shows("Alertes Qualitay", in: window) }, "\(stacks(in: window))")

        root.openInDetail(
            TopicReaderModel(
                target: ReaderTarget(source: .topic(TopicID(category: .forum(13), topic: 5))), title: "Sujet 5",
                source: hosted.environment.topicPages, renderOptions: hosted.environment.reader.settings.renderOptions
            ),
            for: .qualityAlerts
        )
        let pushed = await settle(window) { stacks(in: window).contains { $0.suffix(2) == ["Alertes Qualitay", "Sujet 5 p1"] } }
        #expect(pushed, "the cover screen did not push the topic: \(stacks(in: window))")

        unfold(window, host: hosted.host)
        // Portrait: the topic alone, so the list column is off screen (`DuoSplitColumns`).
        let beside = await settle(window) { !hasTabBar(window) && split(in: window) != nil && shows("Sujet 5 p1", in: window) }
        #expect(beside, "unfolded: tab bar \(hasTabBar(window)), \(stacks(in: window))")
        #expect(root.detailReaders[.qualityAlerts] != nil)
    }
}
