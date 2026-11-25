import Foundation
import Testing

/// #1150: a sheet closes with the system close button (`SheetCloseToolbarItem`), never with a text « Fermer » in a toolbar, and never
/// on the confirm side. HIG › Toolbars: "don't use a text label that says Back or Close".
struct SheetCloseSourceTests {
    private static let appSources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "SwiftHFR")

    private static let sharedFile = "Common/SheetCloseToolbarItem.swift"
    /// Not a sheet: the offline-save progress banner's own dismiss button (an icon-only `xmark`, not in a toolbar).
    private static let exempt: Set<String> = ["Offline/ReaderOfflineSave.swift"]

    private static func sources() throws -> [(file: String, text: String)] {
        let root = appSources.standardizedFileURL.path
        let enumerator = try #require(FileManager.default.enumerator(at: appSources, includingPropertiesForKeys: nil))
        var result: [(file: String, text: String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let file = String(url.standardizedFileURL.path.dropFirst(root.count + 1))
            result.append((file, try String(contentsOf: url, encoding: .utf8)))
        }
        return result
    }

    /// The 1-based lines that build a text button « Fermer » (an `xmark` symbol variant is a close button too, but must be the shared one).
    static func textCloseButtons(in text: String) -> [Int] {
        text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { index, line in
            line.contains(/Button\("Fermer"/) ? index + 1 : nil
        }
    }

    @Test func detectsTextAndSymbolButtons() {
        #expect(Self.textCloseButtons(in: "ToolbarItem { Button(\"Fermer\") { dismiss() } }") == [1])
        #expect(Self.textCloseButtons(in: "a\nButton(\"Fermer\", systemImage: \"xmark\") {}") == [2])
        #expect(Self.textCloseButtons(in: "Button(role: .close) { dismiss() }").isEmpty)
    }

    @Test func theSharedItemExistsAndUsesTheCloseRole() throws {
        let shared = try #require(try Self.sources().first { $0.file == Self.sharedFile })
        #expect(shared.text.contains("role: .close"))
        #expect(shared.text.contains(".cancellationAction"))
    }

    @Test func noToolbarBuildsATextCloseButtonOutsideTheSharedItem() throws {
        let offenders = try Self.sources().filter { $0.file != Self.sharedFile && !Self.exempt.contains($0.file) }
            .flatMap { source in Self.textCloseButtons(in: source.text).map { "\(source.file):\($0)" } }
        #expect(offenders.isEmpty, "use SheetCloseToolbarItem: \(offenders)")
    }

    @Test func theNineSheetsUseTheSharedItem() throws {
        let sheets = [
            "Reader/Viewer/ImageViewerView.swift", "Reader/VideoPlayerSheet.swift", "Polls/PollSheet.swift",
            "FilteredPosts/FilteredPostsView.swift", "Smileys/SmileyPickerView.swift", "Composer/Gif/GifPickerView.swift",
            "Composer/ArchivedDraftsView.swift", "Profile/UserProfileView.swift", "Composer/ImageUpload/ImageUploadView.swift",
            "Reader/ReaderPageSheet.swift",
        ]
        let all = try Self.sources()
        for sheet in sheets {
            let source = try #require(all.first { $0.file == sheet }, "\(sheet) not found")
            #expect(source.text.contains("SheetCloseToolbarItem"), "\(sheet)")
        }
    }
}
