import Foundation
import Testing

/// #1177 (HIG › Sheets: one sheet at a time; › Accessibility: a button besides the swipe): the smiley detail and the GIF
/// confirmation are pushed inside their panel's navigation stack, never a third sheet over the composer. The views have no
/// unit seam; this guards their wiring, and the device check (#893) the result.
struct PickerLayersStructureTests {
    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "SwiftHFR/\(path)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func theSmileyDetailIsPushedNotPresented() throws {
        let text = try source("Smileys/SmileyPickerView.swift")
        #expect(text.contains(".navigationDestination(item: $model.presented)"))
        #expect(!text.contains(".sheet(item: $model.presented)"))
        #expect(!text.contains(".sheet("), "no sheet over the smiley panel")
    }

    @Test func theGifConfirmationIsPushedNotPresented() throws {
        let text = try source("Composer/Gif/GifPickerView.swift")
        #expect(text.contains(".navigationDestination(isPresented: isConfirming)"))
        #expect(!text.contains(".sheet(item: $model.selected)"))
        // The confirmation has no stack of its own: it lives in the panel's.
        let confirmation = try #require(text.range(of: "private struct GifConfirmationView"))
        #expect(!text[confirmation.lowerBound...].contains("ThemedNavigationStack {"))
    }
}
