import HFRNetwork
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// #588: the offline save banner is a glass card, not bare text over the page. Rendered over a flat red page in a real
/// window (glass needs one); a bare banner leaves the page's red at every pixel of its row, glass changes the pixels under it.
@MainActor
@Suite(.serialized)
struct OfflineSaveBannerGlassTests {
    private func failedSaver() async -> OfflineSaveModel {
        let fetcher = FakeOfflineFetcher { _ throws(ListLoadError) in throw .offline }
        let saver = OfflineSaveModel(store: EvictionSpy(), fetcher: fetcher)
        await saver.save(page: readerPage(page: 1), count: 1, fallbackTitle: "Sujet")
        return saver
    }

    private func render(window: UIWindow) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard // 8-bit sRGB, so the bytes below are R, G, B
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    /// The banner over a flat red page, once two renders in a row agree (glass settles after a layout pass or two).
    private func snapshot(scheme: ColorScheme, size: DynamicTypeSize = .large) async throws -> UIImage {
        let saver = await failedSaver()
        #expect(saver.state != .idle)
        let host = UIHostingController(rootView: Color.red.ignoresSafeArea().overlay(alignment: .top) {
            OfflineSaveBanner(saver: saver)
        }.environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size))
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 300)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        var last = render(window: window)
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(50))
            let next = render(window: window)
            if next.pngData() == last.pngData() { return next }
            last = next
        }
        return last
    }

    /// A strip of the banner's row between its text and its close button (no glyph there), against a pixel of the bare page: a
    /// bare banner leaves them identical, glass moves each channel by a few levels (7 to 9 in dark over red, more in light).
    private func differsFromPage(_ image: UIImage, columns: Range<Int> = 280..<340) throws -> Bool {
        let cg = try #require(image.cgImage)
        #expect(cg.bitsPerPixel == 32 && image.scale == 1)
        let data = try #require(cg.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        func pixel(_ x: Int, _ y: Int) -> [Int] { (0..<3).map { Int(bytes[y * cg.bytesPerRow + x * 4 + $0]) } }
        let page = pixel(2, 290)
        var differing = 0
        for y in stride(from: 70, to: 90, by: 2) {
            for x in stride(from: columns.lowerBound, to: columns.upperBound, by: 2) {
                if zip(pixel(x, y), page).contains(where: { abs($0 - $1) > 3 }) { differing += 1 }
            }
        }
        return differing > columns.count * 3
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func theBannerHasAGlassFillOverThePage(scheme: ColorScheme) async throws {
        let image = try await snapshot(scheme: scheme)
        #expect(try differsFromPage(image))
    }

    /// A failure message that wraps at an accessibility size keeps its corners inside the glass (a capsule cut them).
    @Test func aWrappedMessageStillGetsTheGlass() async throws {
        let image = try await snapshot(scheme: .light, size: .accessibility3)
        // The card's left padding: glyphs start 16 pt inside the card (x 32), a bare banner's text at x 16.
        #expect(try differsFromPage(image, columns: 20..<30))
    }
}
