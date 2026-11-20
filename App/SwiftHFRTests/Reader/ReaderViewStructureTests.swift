import Foundation
import Testing

/// Guards of `TopicReaderView`'s wiring that no model test reaches (a view is not instantiable in a unit test).
struct ReaderViewStructureTests {
    /// A followed link pushes a reader through this destination: without it `follow(_:)` stays stuck on `linkedReader`, later
    /// taps are ignored and the covered reader's cleanup never runs (a regression of #595's first push removed it). The
    /// destination's binding is `LinkedReader.binding(of:)` since #912 (it keeps the view file short).
    @Test func theReaderStillPresentsAFollowedLink() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "SwiftHFR/Reader/TopicReaderView.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        #expect(text.contains(".navigationDestination(item: LinkedReader.binding(of: model))"))
        #expect(text.contains(".sheet(item: $authorMenu.profile"))
        #expect(text.contains("ReaderAuthorMenuSheet(flow: authorMenu"))
    }
}
