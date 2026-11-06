import HFRModels
import SwiftUI
@testable import SwiftHFR
import Testing
import UIKit

/// Rows per screen, measured on real lists hosted in a window (LOT-169): compact shows more rows than regular.
@MainActor
@Suite(.serialized)
struct ListDensityLayoutTests {
    private func topics() -> [TopicSummary] {
        (1...40).map { number in
            var topic = TopicSummary(
                topicID: TopicID(category: .forum(13), topic: number), title: "Sujet \(number)", path: "/t\(number)",
                starterOrInterlocutors: "membre", readState: number.isMultiple(of: 2) ? .unread : .read
            )
            topic.repliesCount = number
            return topic
        }
    }

    private func threads() -> [PrivateMessageThread] {
        (1...40).map { number in
            var summary = TopicSummary(
                topicID: TopicID(category: .privateMessages, topic: number), title: "Conversation \(number)", path: "/p\(number)",
                starterOrInterlocutors: "membre", readState: .read
            )
            summary.lastPost = LastPost(author: "autre", path: "/p\(number)#bas")
            return PrivateMessageThread(summary: summary, interlocutors: ["membre"], isGroup: false)
        }
    }

    /// Rows fully visible in a 402 × 874 pt window (an iPhone 18 Pro screen).
    private func visibleRows(_ list: some View, density: ListDensity, percent: Int = 100) async -> Int {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene else {
            return -1
        }
        let host = UIHostingController(rootView: list.appTypography(TextScale(percent: percent), density: density))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        var count = 0
        // Polls until the list has laid out its rows (a cold simulator can take a while).
        for _ in 0..<200 {
            try? await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            guard let collection = Self.collectionView(in: host.view) else { continue }
            count = collection.visibleCells.filter { collection.bounds.contains($0.frame) }.count
            if count > 0 { break }
        }
        return count
    }

    private static func collectionView(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView { return collection }
        return view.subviews.lazy.compactMap { collectionView(in: $0) }.first
    }

    @Test func compactShowsMoreTopicRowsThanRegular() async {
        let list = List(topics()) { TopicRowView(topic: $0) }.listStyle(.plain)
        let regular = await visibleRows(list, density: .regular)
        let compact = await visibleRows(list, density: .compact)
        #expect(regular > 0)
        #expect(compact > regular, "regular \(regular), compact \(compact)")
    }

    @Test func compactShowsMoreConversationRowsThanRegular() async {
        let list = List(threads(), id: \.summary.id) { MessageRowView(thread: $0, isUnread: false) }.listStyle(.plain)
        let regular = await visibleRows(list, density: .regular)
        let compact = await visibleRows(list, density: .compact)
        #expect(regular > 0)
        #expect(compact > regular, "regular \(regular), compact \(compact)")
    }

    @Test func seventyPercentShowsMoreRowsThanTheDefault() async {
        let list = List(topics()) { TopicRowView(topic: $0) }.listStyle(.plain)
        let standard = await visibleRows(list, density: .regular)
        let small = await visibleRows(list, density: .regular, percent: 70)
        #expect(standard > 0)
        #expect(small > standard, "100 % \(standard), 70 % \(small)")
    }
}
