import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing
import UIKit

/// LOT-193 (#734): the topic page (the reader) under the OG themes at Dynamic Type XL and AX5, with invented messages and
/// `user1`. The page paints the theme's `surface`; with `OG_SHOT_DIR` set the render is also written as a PNG for the PR.
@MainActor
@Suite(.serialized)
struct ThemeTablePageShotTests: ReaderWebTesting {
    private func page(token: Int) -> ReaderDocument {
        let messages = (1...3).map { number in
            ReaderMessage(
                numreponse: number, author: "user1", isDeleted: false, isContinuation: false, avatarURL: nil,
                dateText: "27-10-2026 10:0\(number):00", editNote: nil, quotedByCount: nil,
                content: MessageContent(html: "<p>Message d'exemple numéro \(number), un texte assez long pour passer à la ligne.</p>")
            )
        }
        let page = ReaderPage(topicID: readerTopic, title: "Sujet d'exemple", currentPage: 1, maxPage: 1, messages: messages)
        return ReaderDocument(
            token: token, html: TopicHTMLBuilder.document(for: page, token: token), anchor: nil, keepsScrollPosition: false
        )
    }

    @Test(arguments: ["og-clair", "og-gris"], [(UIContentSizeCategory.large, "xl"), (.accessibilityExtraExtraExtraLarge, "ax5")])
    func theTopicPageShowsTheThemesSurface(id: String, size: (UIContentSizeCategory, String)) async throws {
        let catalog = ThemeCatalog.bundled
        let model = ThemeSettingsModel(store: InMemorySettingsStore(), catalog: catalog)
        model.select(try #require(catalog.themes.first { $0.id == id }))
        let (controller, recorder) = makeController(transport: imageTransport())
        let window = try #require(recorder.window)
        defer { window.isHidden = true }
        window.overrideUserInterfaceStyle = .light
        window.traitOverrides.preferredContentSizeCategory = size.0
        controller.theme = model.appearance
        controller.show(page(token: 1))
        #expect(await until { recorder.ready == [1] })
        try await Task.sleep(for: .seconds(1))
        let image = try await controller.webView.takeSnapshot(configuration: nil)
        if let folder = ProcessInfo.processInfo.environment["OG_SHOT_DIR"], let data = image.pngData() {
            try data.write(to: URL(fileURLWithPath: folder).appending(path: "page-\(id)-\(size.1).png"))
        }
        let surface = try #require(model.appearance.themeVariants?.light.surface)
        let scale = image.scale
        let probe = try #require(image.cgImage?.cropping(to: CGRect(x: 4 * scale, y: 400 * scale, width: 1, height: 1)))
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(probe, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let expected = [Int(surface.red), Int(surface.green), Int(surface.blue)]
        #expect(zip(pixel.prefix(3).map(Int.init), expected).allSatisfy { abs($0 - $1) <= 3 }, "pixel \(pixel), surface \(expected)")
    }
}
