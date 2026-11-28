import HFRModels
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// LOT-193 (#734): renders the OG themes' table look on a real topic list, at Dynamic Type XL and AX5, and checks it wraps
/// without clipping. Invented titles and `user1` only. With `OG_SHOT_DIR` set (a folder) it also writes each render as a PNG for
/// the PR; without it, the checks alone run.
@MainActor
@Suite(.serialized)
struct ThemeTableScreenshotTests {
    private func topics() -> [TopicSummary] {
        (1...6).map { number in
            var topic = TopicSummary(
                topicID: TopicID(category: .forum(13), topic: number),
                title: "Sujet d'exemple numéro \(number), avec un titre assez long pour passer à la ligne", path: "/t\(number)",
                starterOrInterlocutors: "user1", readState: number.isMultiple(of: 2) ? .unread : .read
            )
            topic.repliesCount = number * 12
            return topic
        }
    }

    private func threads() -> [PrivateMessageThread] {
        topics().map { topic in
            var summary = topic
            summary.lastPost = LastPost(author: "user1", path: "/p#bas", date: Date(timeIntervalSince1970: 1_700_000_000))
            return PrivateMessageThread(summary: summary, interlocutors: ["user1"], isGroup: false)
        }
    }

    private struct TableScreen: View {
        let model: ThemeSettingsModel
        let topics: [TopicSummary]
        let threads: [PrivateMessageThread]
        let size: DynamicTypeSize
        var body: some View {
            List {
                Group {
                    Section {
                        if threads.isEmpty {
                            ForEach(Array(topics.enumerated()), id: \.element.id) { index, topic in
                                TopicRowView(topic: topic).themedRowText()
                                    .listLookRow(isSelected: false, isAlternate: index.isMultiple(of: 2) == false)
                            }
                        } else {
                            ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
                                MessageRowView(thread: thread, isUnread: index == 1).themedRowText()
                                    .listLookRow(isSelected: false, isAlternate: index.isMultiple(of: 2) == false)
                            }
                        }
                    } header: { Text("Forum d'exemple").themedBandHeader() }
                }.listLookRows()
            }
            .listStyle(.insetGrouped)
            .themedListScreen()
            .environment(\.dynamicTypeSize, size)
            .appTheme(model)
        }
    }

    private func render(_ id: String, _ size: DynamicTypeSize, label: String, messages: Bool = false) async throws -> (UIImage, UIWindow) {
        let catalog = ThemeCatalog.bundled
        let model = ThemeSettingsModel(store: InMemorySettingsStore(), catalog: catalog)
        model.select(try #require(catalog.themes.first { $0.id == id }))
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let screen = TableScreen(model: model, topics: topics(), threads: messages ? threads() : [], size: size)
        window.rootViewController = UIHostingController(rootView: screen)
        window.isHidden = false
        try await Task.sleep(for: .seconds(1.5))
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        if let folder = ProcessInfo.processInfo.environment["OG_SHOT_DIR"], let data = image.pngData() {
            try data.write(to: URL(fileURLWithPath: folder).appending(path: "\(messages ? "messages-" : "")\(id)-\(label).png"))
        }
        return (image, window)
    }

    /// Both OG themes at XL and AX5: the list lays out rows (none clipped to nothing) and paints the band and both cell colours.
    @Test(arguments: ["og-clair", "og-gris"], [(DynamicTypeSize.xLarge, "xl"), (.accessibility5, "ax5")])
    func theTableLookWrapsAtLargeSizes(id: String, size: (DynamicTypeSize, String)) async throws {
        let (image, window) = try await render(id, size.0, label: size.1)
        defer { window.isHidden = true }
        let host = try #require(window.rootViewController?.view)
        let collection = try #require(Self.collectionView(in: host))
        let cells = collection.visibleCells
        #expect(!cells.isEmpty && cells.allSatisfy { $0.frame.width > 300 && $0.frame.height > 30 }, "\(cells.map(\.frame))")
        // AX5 rows grow taller than XL's: the text wrapped instead of clipping.
        #expect(image.size.width == 402)
    }

    /// The conversation list under both OG themes at XL and AX5 (the same table look on the message rows).
    @Test(arguments: ["og-clair", "og-gris"], [(DynamicTypeSize.xLarge, "xl"), (.accessibility5, "ax5")])
    func theMessageListWrapsAtLargeSizes(id: String, size: (DynamicTypeSize, String)) async throws {
        let (_, window) = try await render(id, size.0, label: size.1, messages: true)
        defer { window.isHidden = true }
        let host = try #require(window.rootViewController?.view)
        let cells = try #require(Self.collectionView(in: host)).visibleCells
        #expect(!cells.isEmpty && cells.allSatisfy { $0.frame.width > 300 && $0.frame.height > 30 }, "\(cells.map(\.frame))")
    }

    private static func collectionView(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView { return collection }
        return view.subviews.lazy.compactMap { collectionView(in: $0) }.first
    }
}
