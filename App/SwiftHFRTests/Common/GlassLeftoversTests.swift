import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRParsing
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// A lookup or search that answers only once its task is cancelled (the test cancels it), so the screen stays in its "searching" state.
private struct Hanging: SmileyLookups, TopicSearching {
    func search(_ text: String, requireAll: Bool) async throws(SmileyLookupError) -> [ForumSmiley] {
        while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(50)) }
        return []
    }

    func wiki(code: String) async throws(SmileyLookupError) -> SmileyWikiDetail { throw .invalidCode }

    func search(_ query: TopicSearchQuery) async throws(TopicSearchError) -> TopicSearchResult {
        while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(50)) }
        throw .missingToken
    }
}

/// #1138: the topic-search progress panel and the smiley search options strip are system glass, not a material or a bar fill.
/// Hosted in a real window (glass needs one); the layer tree is what tells glass from a material.
@MainActor
@Suite(.serialized)
struct GlassLeftoversTests {
    private func window(_ root: some View, scheme: ColorScheme) throws -> (UIWindow, UIHostingController<AnyView>) {
        let host = UIHostingController(rootView: AnyView(root.environment(\.colorScheme, scheme)))
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        return (window, host)
    }

    /// Polls (laying out each time) until `condition` holds; false after 15 s, so the caller's expectation ends red.
    private func eventually(_ window: UIWindow, _ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<300 {
            window.rootViewController?.view.layoutIfNeeded()
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    private func classes(of layer: CALayer) -> [String] {
        [String(describing: type(of: layer))] + (layer.sublayers ?? []).flatMap { classes(of: $0) }
    }

    private func classes(of view: UIView) -> [String] {
        [String(describing: type(of: view))] + classes(of: view.layer) + view.subviews.flatMap { classes(of: $0) }
    }

    /// Saves a screenshot and the class names under `TEST_RUNNER_SHOT_DIR` (evidence runs only; nothing without it).
    private func record(_ window: UIWindow, name: String, scheme: ColorScheme) {
        guard let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] else { return }
        let tag = ProcessInfo.processInfo.environment["SHOT_TAG"] ?? "x"
        let base = "\(dir)/\(tag)-\(name)-\(scheme == .dark ? "dark" : "light")"
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try? image.pngData()?.write(to: URL(fileURLWithPath: base + ".png"))
        let all = classes(of: window)
        let names = Set(all).sorted().map { key in "\(key) x\(all.filter { $0 == key }.count)" }.joined(separator: "\n")
        try? names.write(toFile: base + ".txt", atomically: true, encoding: .utf8)
    }

    /// A hosted screen: its window, and what cancels its pending work.
    private struct Screen {
        let window: UIWindow
        let model: AnyObject
        let stop: () -> Void
    }

    private func topicSheet(scheme: ColorScheme, searching: Bool) throws -> Screen {
        let model = TopicSearchModel(topic: TopicID(category: .forum(13), topic: 28563), searcher: Hanging())
        model.word = "napolitaine"
        let (window, _) = try window(TopicSearchSheet(model: model, open: { _ in }), scheme: scheme)
        let task = searching ? Task { _ = await model.submit() } : nil
        return Screen(window: window, model: model, stop: { task?.cancel(); model.cancel(); window.isHidden = true })
    }

    private func smileySheet(scheme: ColorScheme) throws -> Screen {
        let search = SmileySearchModel(
            lookups: Hanging(), history: SmileySearchHistoryStore(persistence: InMemorySmallStorePersistence())
        )
        let picker = SmileyPickerModel(
            catalogue: [], store: AppSmileyFavoritesStore(persistence: InMemorySmallStorePersistence()), account: "user1",
            search: search
        )
        let (window, _) = try window(SmileyPickerView(model: picker, onInsert: { _ in }), scheme: scheme)
        search.text = "miaou"
        search.submit(requireAll: false)
        return Screen(window: window, model: picker, stop: { search.clear(); window.isHidden = true })
    }

    /// RGB of the pixel at (`fx`, `fy`) of the window, as fractions of its size, decoded to 8-bit sRGB.
    private func pixel(_ window: UIWindow, _ fx: Double, _ fy: Double) -> [Int] {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let cg = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return [] }
        var rgba = [UInt8](repeating: 0, count: 4)
        let x = min(cg.width - 1, Int(fx * Double(cg.width))), y = min(cg.height - 1, Int(fy * Double(cg.height)))
        rgba.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
        }
        return rgba.prefix(3).map(Int.init)
    }

    /// The frame, in window coordinates, of the first view whose class name contains `name`.
    private func frame(ofViewNamed name: String, in window: UIWindow) -> CGRect? {
        func find(_ view: UIView) -> UIView? {
            if String(describing: type(of: view)).contains(name) { return view }
            return view.subviews.lazy.compactMap(find).first
        }
        guard let view = find(window) else { return nil }
        return view.convert(view.bounds, to: window)
    }

    /// RGB at window point `point` (see `pixel(_:_:_:)`).
    private func pixel(_ window: UIWindow, at point: CGPoint) -> [Int] {
        pixel(window, point.x / window.bounds.width, point.y / window.bounds.height)
    }

    private func count(_ name: String, in names: [String]) -> Int { names.filter { $0 == name }.count }

    // The class names below are private UIKit/SwiftUI internals, so these tests are coupled to the OS: a rename makes them
    // fail (never pass by accident); re-capture the names with `TEST_RUNNER_SHOT_DIR` (see `record`) and update them then.
    private static let glass = "UIPlatformGlassInteractionView"
    private static let backdrop = "CABackdropLayer"

    /// The panel adds one glass view to the sheet (a material adds none: the buttons of the bar are the only other glass), and
    /// nothing else under it: a material kept under the glass adds backdrop layers (11 with glass alone, 13 with both). The exact
    /// count is OS-coupled like the class names: an OS update that changes it fails here, and is re-captured then.
    @Test(arguments: [ColorScheme.light, .dark])
    func theTopicSearchProgressPanelIsGlass(scheme: ColorScheme) async throws {
        let idleScreen = try topicSheet(scheme: scheme, searching: false)
        defer { idleScreen.stop() }
        let idleReady = try await eventually(idleScreen.window) { count(Self.glass, in: classes(of: idleScreen.window)) >= 2 }
        #expect(idleReady)
        let idle = classes(of: idleScreen.window)
        idleScreen.stop()

        let screen = try topicSheet(scheme: scheme, searching: true)
        defer { screen.stop() }
        let glassFound = try await eventually(screen.window) {
            count(Self.glass, in: classes(of: screen.window)) > count(Self.glass, in: idle)
        }
        #expect(glassFound)
        record(screen.window, name: "topicsearch", scheme: scheme)
        let searching = classes(of: screen.window)
        #expect(count(Self.glass, in: searching) == count(Self.glass, in: idle) + 1)
        #expect(count(Self.backdrop, in: searching) - count(Self.backdrop, in: idle) == 11)
    }

    /// The options strip is a system bottom bar (a scroll-edge pocket bar) with no fill: the row between its label and its
    /// switch shows the page, where `.background(.bar)` tinted it (5 levels in light).
    @Test(arguments: [ColorScheme.light, .dark])
    func theSmileySearchOptionsAreASystemBottomBar(scheme: ColorScheme) async throws {
        let screen = try smileySheet(scheme: scheme)
        defer { screen.stop() }
        let found = try await eventually(screen.window) {
            classes(of: screen.window).contains { $0.contains("ScrollPocketBarInteraction") }
        }
        #expect(found)
        record(screen.window, name: "smiley", scheme: scheme)
        #expect((screen.model as? SmileyPickerModel)?.search?.isSearching == true)
        let bar = try #require(frame(ofViewNamed: "ScrollPocketBarInteraction", in: screen.window))
        let page = pixel(screen.window, 0.5, 0.7)
        #expect(!page.isEmpty)
        // The switch's track (its right end; the knob is white) is drawn there, a frame after the bar (polled): a blank render
        // or a hidden strip would show the page and time out red.
        let point = CGPoint(x: screen.window.bounds.width * 0.95, y: bar.midY)
        let drawn = try await eventually(screen.window) {
            !zip(pixel(screen.window, at: point), page).allSatisfy { abs($0 - $1) <= 1 }
        }
        #expect(drawn, "switch \(pixel(screen.window, at: point)) against the page \(page), bar \(bar)")
        // Rows inside the bar (the label and the switch sit on its middle), the column between them, and the switch itself.
        let rows = [0.25, 0.5, 0.75].map { bar.minY + bar.height * $0 }
        for y in rows {
            let strip = pixel(screen.window, at: CGPoint(x: screen.window.bounds.midX, y: y))
            #expect(zip(strip, page).allSatisfy { abs($0 - $1) <= 1 }, "y \(y): \(strip) against the page \(page)")
        }
    }
}
