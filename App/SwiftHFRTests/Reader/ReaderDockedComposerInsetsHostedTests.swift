import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit
import WebKit

/// #1285, #1286 (review of #1377): the real reader under its docked reply composer at its cap. The page is exactly the space between
/// the navigation bar and the bar: the web view's top inset ends at the navigation bar's bottom, its bottom one at the bar's top.
/// The reader's bottom pull icon (#1207) once gave the page a minimum height of about 135 pt: with a capped card above the
/// keyboard, the page overflowed under both bars (40 pt each on the iPhone 18 Pro simulator, iOS 27.2) and the bar with it.
@MainActor
@Suite(.serialized)
struct ReaderDockedComposerInsetsHostedTests {
    @Test(.enabled(if: UIDevice.current.userInterfaceIdiom == .phone))
    func thePageUnderADockedComposerAtItsCapEndsAtBothBars() async throws {
        // The space a keyboard leaves on a phone (a window of this size has no safe area): the capped card (six lines with no
        // keyboard measured) and the page's former 135 pt minimum do not fit together under the navigation bar.
        let hosted = try await Self.host(frame: CGRect(x: 0, y: 0, width: 390, height: 420))
        defer { hosted.window.isHidden = true }
        let (reader, window, box) = (hosted.reader, hosted.window, hosted.box)
        // A long draft: the composer opens on it, at its cap.
        let target = try #require(reader.replyTarget)
        let text = (1...30).map { "Ligne \($0) du message." }.joined(separator: "\n")
        try await hosted.drafts.save(text, for: target.draftContext, account: ComposerFixture.account)
        await reader.requestReply()
        let webView = try #require(Self.find(WKWebView.self, in: window))
        try await Self.settle(window: window, webView: webView, box: box)
        let navigationBottom = try #require(Self.find(UINavigationBar.self, in: window)).windowFrame(window).maxY
        let card = try #require(box.frames[.card])
        // The bar starts at the floating buttons' row: what the measured top (`ComposerCardLayout.top`) holds above the card.
        let barTop = card.minY - box.layout.top
        let insets = webView.scrollView.contentInset
        let webFrame = webView.windowFrame(window)
        #expect(abs(webFrame.minY + insets.top - navigationBottom) < 1, "top inset \(insets.top), navigation bar \(navigationBottom)")
        #expect(abs(webFrame.maxY - insets.bottom - barTop) < 1, "bottom inset \(insets.bottom), bar's top \(barTop)")
        #expect(card.maxY < window.bounds.maxY, "the card \(card) on screen")
        // The menu's confirmation sits on the page, above the bar (#853), not under it.
        let banner = try await Self.feedbackFrame("Lien copié", of: reader, in: window)
        #expect(banner.maxY <= barTop + 0.5 && banner.minY >= navigationBottom - 0.5, "banner \(banner), bar's top \(barTop)")
    }

    /// #1207's pull icons over a page on screen, once the review of #1377 moved them to overlays: a pull at either end draws its
    /// icon, at the top under the navigation bar and at the bottom (an overlay of a view that builds nothing draws nothing).
    @Test(.enabled(if: UIDevice.current.userInterfaceIdiom == .phone))
    func bothPullIconsShowOverAShownPage() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let hosted = try await Self.host(frame: scene.effectiveGeometry.coordinateSpace.bounds)
        defer { hosted.window.isHidden = true }
        let (reader, window) = (hosted.reader, hosted.window)
        let navigationBottom = try #require(Self.find(UINavigationBar.self, in: window)).windowFrame(window).maxY
        try await Task.sleep(for: .seconds(1))
        let rest = try #require(PixelSnapshot(window))
        reader.pullTop = 1
        reader.pullBottom = 1
        var changed: [CGFloat] = []
        _ = await Self.until {
            changed = PixelSnapshot(window).map { rest.changedRows(in: $0, aroundX: window.bounds.midX) } ?? []
            return changed.contains { $0 < window.bounds.midY } && changed.contains { $0 > window.bounds.midY }
        }
        let top = changed.filter { $0 < window.bounds.midY }
        let bottom = changed.filter { $0 > window.bounds.midY }
        #expect(!top.isEmpty && !bottom.isEmpty, "rows drawn by the pulls: \(changed.min() ?? -1)…\(changed.max() ?? -1)")
        // The top icon just under the navigation bar, where it was before #1377: its first drawn row 20 pt under the bar on the
        // iPhone 18 Pro simulator, iOS 27.2, both ways (the bar's glass may pick it up above: only the page's rows count).
        let topEdge = top.filter { $0 >= navigationBottom }.min() ?? .infinity
        #expect(topEdge <= navigationBottom + 24, "the top icon starts at \(topEdge), the navigation bar ends at \(navigationBottom)")
    }
}

extension ReaderDockedComposerInsetsHostedTests {
    fileprivate struct Hosted {
        let reader: TopicReaderModel
        let window: UIWindow
        let drafts: DraftStore
        let box: InsetsFramesBox
    }

    /// The real reader in a window of `frame`, its fixture page shown.
    fileprivate static func host(frame: CGRect) async throws -> Hosted {
        let box = InsetsFramesBox()
        let pages = FakeTopicPages { _ in
            var page = quotablePage(numbers: Array(100..<110))
            page.pageURL = URL(string: "https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm")
            return page
        }
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic), page: 1), title: "Sujet", source: pages)
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let settings = ExperimentalSettings(store: InMemorySettingsStore())
        settings.set(.modernComposer, isOn: true)
        let root = DockedReaderHost(
            reader: reader, composer: ComposerFixture.services(poster: ScriptedPoster([]), drafts: drafts), settings: settings
        )
        .environment(\.composerLayoutProbe, box.probe)
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = frame
        window.rootViewController = UIHostingController(rootView: root)
        window.isHidden = false
        try #require(await until { reader.hasShownDocument && reader.replyTarget != nil }, "the page is shown")
        return Hosted(reader: reader, window: window, drafts: drafts, box: box)
    }

    /// Until the composer shows its long draft and the frames and insets stop moving (four equal reads in a row, #1194).
    fileprivate static func settle(window: UIWindow, webView: WKWebView, box: InsetsFramesBox) async throws {
        var last: [CGFloat] = []
        var steady = 0
        for _ in 0..<200 where steady < 4 {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            let insets = webView.scrollView.contentInset
            let now = [insets.top, insets.bottom, box.frames[.card]?.minY ?? -1, box.layout.text]
            steady = box.layout.text > ComposerCardLayout.maximumLines * box.layout.line && now == last ? steady + 1 : 0
            last = now
        }
        try #require(steady >= 4, "never settled: card \(String(describing: box.frames[.card])), text \(box.layout.text)")
    }

    /// The frame of the menu's confirmation `text` once the reader shows it.
    fileprivate static func feedbackFrame(_ text: String, of reader: TopicReaderModel, in window: UIWindow) async throws -> CGRect {
        HostedAccessibility.beginAutomation()
        defer { HostedAccessibility.endAutomation() }
        reader.showMenuFeedback(text)
        let feedback = { HostedAccessibility.elements(under: window).first { $0.accessibilityLabel == text } }
        try #require(await until { feedback() != nil }, "the confirmation is shown")
        return try #require(feedback()).accessibilityFrame
    }

    fileprivate static func until(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(50)) }
        return condition()
    }

    fileprivate static func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let found = view as? T { return found }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }
}

extension UIView {
    fileprivate func windowFrame(_ window: UIWindow) -> CGRect { convert(bounds, to: window) }
}

/// A window drawn at one pixel per point, as RGBA bytes: what a pull icon changes on screen (it is hidden from accessibility).
@MainActor
private struct PixelSnapshot {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(_ window: UIWindow) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let cgImage = image.cgImage else { return nil }
        let (columns, rows) = (cgImage.width, cgImage.height)
        var pixels = [UInt8](repeating: 0, count: columns * rows * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: columns * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ).map { $0.draw(cgImage, in: CGRect(x: 0, y: 0, width: columns, height: rows)); return true } ?? false
        }
        guard drawn else { return nil }
        width = columns
        height = rows
        bytes = pixels
    }

    /// The rows (points from the top) where `other` differs from this snapshot within 30 pt of `x`.
    func changedRows(in other: PixelSnapshot, aroundX x: CGFloat) -> [CGFloat] {
        guard other.width == width, other.height == height else { return [] }
        let columns = max(0, Int(x) - 30)..<min(width, Int(x) + 30)
        return (0..<height).filter { row in
            columns.contains { column in
                let index = (row * width + column) * 4
                return (0..<3).contains { abs(Int(bytes[index + $0]) - Int(other.bytes[index + $0])) > 24 }
            }
        }
        .map { CGFloat($0) }
    }
}

@MainActor
private final class InsetsFramesBox {
    var frames: [ComposerLayoutProbe.Part: CGRect] = [:]
    var layout = ComposerCardLayout()

    var probe: ComposerLayoutProbe {
        ComposerLayoutProbe(frame: { [weak self] part, frame in self?.frames[part] = frame }, layout: { [weak self] in self?.layout = $0 })
    }
}

/// The real reader in its navigation stack, its reply composer docked (« Composer moderne » on).
private struct DockedReaderHost: View {
    let reader: TopicReaderModel
    let composer: ComposerServices
    let settings: ExperimentalSettings

    var body: some View {
        NavigationStack {
            TopicReaderView(
                model: reader,
                services: ReaderServices(
                    imageFetcher: ReaderImageFetcher(transport: MockTransport(replies: [])),
                    settings: ReaderSettings(
                        autoLoadsThirdPartyImages: { false }, renderOptions: { ReaderRenderOptions() }, swipesPages: { false }
                    ),
                    profiles: FakeUserProfiles([])
                ),
                composer: composer
            )
        }
        .environment(settings)
        // A short window reads as compact height, where the composer opens full: a phone in portrait, keyboard up, is regular.
        .environment(\.verticalSizeClass, .regular)
    }
}
