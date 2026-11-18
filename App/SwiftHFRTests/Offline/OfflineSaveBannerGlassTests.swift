import HFRNetwork
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// #588: the offline save banner is a glass capsule, not bare text over the page. Rendered over a flat red page in a real
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

    private func snapshot(scheme: ColorScheme) async throws -> UIImage {
        let saver = await failedSaver()
        #expect(saver.state != .idle)
        let host = UIHostingController(rootView: Color.red.ignoresSafeArea().overlay(alignment: .top) {
            OfflineSaveBanner(saver: saver)
        }.environment(\.colorScheme, scheme))
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 200)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
    }

    /// A strip of the banner's row between its text and its close button (no glyph there), against a pixel of the bare page:
    /// a bare banner leaves them identical.
    private func differsFromPage(_ image: UIImage) throws -> Bool {
        let cg = try #require(image.cgImage)
        let data = try #require(cg.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        let step = cg.bitsPerPixel / 8
        func pixel(_ x: Int, _ y: Int) -> [Int] { (0..<3).map { Int(bytes[y * cg.bytesPerRow + x * step + $0]) } }
        let page = pixel(2, Int(190 * image.scale))
        var differing = 0
        for y in stride(from: Int(70 * image.scale), to: Int(90 * image.scale), by: 2) {
            for x in stride(from: Int(280 * image.scale), to: Int(340 * image.scale), by: 2) {
                if zip(pixel(x, y), page).contains(where: { abs($0 - $1) > 12 }) { differing += 1 }
            }
        }
        return differing > 100
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func theBannerHasAGlassFillOverThePage(scheme: ColorScheme) async throws {
        let image = try await snapshot(scheme: scheme)
        #expect(try differsFromPage(image))
    }
}
