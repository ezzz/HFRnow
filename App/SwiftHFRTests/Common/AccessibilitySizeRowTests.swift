import HFRModels
import SwiftUI
@testable import SwiftHFR
import Testing
import UIKit

/// Reads the size SwiftUI laid a hosted view out at.
@MainActor
private final class RowSizeBox { var size: CGSize = .zero }

/// #1439: at the accessibility Dynamic Type sizes the Messages and topic rows stack what sits side by side at the default size,
/// measured on the real rows hosted in a window 402 pt wide (an iPhone 18 Pro). Each check compares two rows that differ only by
/// the text under test, so the avatar, capsule and insets cancel out and the difference is the room that text was given.
@MainActor
@Suite(.serialized)
struct AccessibilitySizeRowTests {
    private static let width: CGFloat = 402
    private static let accessibilitySize = DynamicTypeSize.accessibility3

    /// The height of `content` laid out `width` points wide at `size`.
    private func height(_ content: some View, width: CGFloat = Self.width, size: DynamicTypeSize) async throws -> CGFloat {
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let box = RowSizeBox()
        let view = content
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self, of: \.size) { box.size = $0 }
            .environment(\.dynamicTypeSize, size)
            .frame(maxHeight: .infinity, alignment: .top)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: Self.width, height: 4_000)
        window.rootViewController = UIHostingController(rootView: view)
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<60 where box.size == .zero {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
        }
        return box.size.height
    }

    private func thread(title: String) -> PrivateMessageThread {
        var summary = TopicSummary(
            topicID: TopicID(category: .privateMessages, topic: 1), title: title, path: "/p1", starterOrInterlocutors: "membre",
            readState: .unread
        )
        summary.lastPost = LastPost(author: "autre", path: "/p1#bas", date: .now.addingTimeInterval(-600))
        return PrivateMessageThread(summary: summary, isUnreadByOthers: true, interlocutors: ["membre"])
    }

    /// Item 1: the « non lu » capsule, the avatar and the unread dot left the title about a quarter of the width (one word a line).
    /// The title now takes at least 60 % of the row: its share of the row's height is no more than it is at 60 % of the width.
    @Test func aMessageRowTitleHasMostOfTheRowWidthAtAnAccessibilitySize() async throws {
        let long = "Un sujet de conversation assez long pour passer à la ligne plusieurs fois de suite"
        let short = "Sujet"
        let size = Self.accessibilitySize
        let longRow = try await height(MessageRowView(thread: thread(title: long), isUnread: true), size: size)
        let shortRow = try await height(MessageRowView(thread: thread(title: short), isUnread: true), size: size)
        let style = ListDensity.regular.titleStyle
        let column = Self.width * 0.6
        let longText = try await height(Text(long).scaledFont(style).fontWeight(.semibold), width: column, size: size)
        let shortText = try await height(Text(short).scaledFont(style).fontWeight(.semibold), width: column, size: size)
        #expect(longRow > 0 && longText > shortText, "rows \(longRow) / \(shortRow), text \(longText) / \(shortText)")
        #expect(
            longRow - shortRow <= longText - shortText + 1,
            "the title took \(longRow - shortRow) pt of height; at 60 % of the width it takes \(longText - shortText) pt"
        )
    }

    /// What VoiceOver hears for the hosted row: the stacked row reads in the same order as the side-by-side one (the unread dot,
    /// now above the text, is still read last).
    private func spokenLabel(of thread: PrivateMessageThread, size: DynamicTypeSize) async throws -> String {
        HostedAccessibility.beginAutomation()
        defer { HostedAccessibility.endAutomation() }
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: Self.width, height: 1_200)
        let list = List { MessageRowView(thread: thread, isUnread: true) }.listStyle(.plain).environment(\.dynamicTypeSize, size)
        window.rootViewController = UIHostingController(rootView: list)
        window.isHidden = false
        defer { window.isHidden = true }
        let title = thread.summary.displayTitle
        var found: [String] = []
        for _ in 0..<100 where found.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            found = HostedAccessibility.elements(under: window).compactMap(\.accessibilityLabel).filter { $0.contains(title) }
        }
        return try #require(found.first, "the row is not in the accessibility tree")
    }

    @Test(.timeLimit(.minutes(1)))
    func aMessageRowIsSpokenInTheSameOrderAtEverySize() async throws {
        let row = thread(title: "Sujet")
        let standard = try await spokenLabel(of: row, size: .large)
        let large = try await spokenLabel(of: row, size: Self.accessibilitySize)
        #expect(standard.hasSuffix("Non lu"), "default: \(standard)")
        #expect(large == standard, "accessibility size: \(large); default: \(standard)")
    }

    private func topic(lastPost: LastPost?) -> TopicSummary {
        TopicSummary(
            topicID: TopicID(category: .forum(13), topic: 1), title: "Les écrans UltraWide 21:9", path: "/t1", pageCount: 452,
            lastPost: lastPost, flagPath: "/t1#t9", currentPage: 452, readState: .read
        )
    }

    /// Item 4: side by side, « last poster - date » was cut to one line (the date lost to the ellipsis) and « ⚑ 452 / 452 » wrapped.
    /// Stacked, the right side gets the whole width and every line it needs.
    @Test func theTopicRowFooterShowsTheWholeDateAtAnAccessibilitySize() async throws {
        let size = Self.accessibilitySize
        let date = Date.now.addingTimeInterval(-40 * 86_400)
        let post = LastPost(author: "un-membre-au-pseudo-assez-long", path: "/t1#bas", date: date)
        let trailing = try #require(TopicRowInfoLine.trailing(topic(lastPost: post)))
        let full = try await height(Text(trailing).scaledFont(.caption), size: size)
        let oneLine = try await height(Text(trailing).scaledFont(.caption).lineLimit(1), size: size)
        // The case of the defect: the footer's right side needs more than one line at this size.
        try #require(full > oneLine + 1, "the footer fits one line (\(full) / \(oneLine)): the test would not see a truncation")
        let with = try await height(LegacyTopicRowView(topic: topic(lastPost: post)), size: size)
        let without = try await height(LegacyTopicRowView(topic: topic(lastPost: nil)), size: size)
        #expect(with - without >= full - 0.5, "the right side added \(with - without) pt; whole, it is \(full) pt")
    }

    /// Guard: at the default size the footer keeps its two sides on one line.
    @Test func theTopicRowFooterStaysOnOneLineAtTheDefaultSize() async throws {
        let post = LastPost(author: "membre", path: "/t1#bas", date: .now.addingTimeInterval(-40 * 86_400))
        let with = try await height(LegacyTopicRowView(topic: topic(lastPost: post)), size: .large)
        let without = try await height(LegacyTopicRowView(topic: topic(lastPost: nil)), size: .large)
        #expect(with > 0 && abs(with - without) < 0.5, "with the right side \(with), without \(without)")
    }
}
