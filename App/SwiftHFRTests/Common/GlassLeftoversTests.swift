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

/// A lookup or search that never answers, so the screen stays in its "searching" state.
private struct Hanging: SmileyLookups, TopicSearching {
    func search(_ text: String, requireAll: Bool) async throws(SmileyLookupError) -> [ForumSmiley] {
        try? await Task.sleep(for: .seconds(3600))
        return []
    }

    func wiki(code: String) async throws(SmileyLookupError) -> SmileyWikiDetail { throw .invalidCode }

    func search(_ query: TopicSearchQuery) async throws(TopicSearchError) -> TopicSearchResult {
        try? await Task.sleep(for: .seconds(3600))
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

    private func settle(_ window: UIWindow) async throws {
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            window.rootViewController?.view.layoutIfNeeded()
        }
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

    private func topicSheet(scheme: ColorScheme, searching: Bool) async throws -> (UIWindow, [String]) {
        let model = TopicSearchModel(topic: TopicID(category: .forum(13), topic: 28563), searcher: Hanging())
        model.word = "napolitaine"
        let (window, host) = try window(TopicSearchSheet(model: model, open: { _ in }), scheme: scheme)
        _ = host
        if searching { Task { _ = await model.submit() } }
        try await settle(window)
        #expect((model.state == .searching) == searching)
        return (window, classes(of: window))
    }

    private func smileySheet(scheme: ColorScheme) async throws -> (UIWindow, [String]) {
        let search = SmileySearchModel(
            lookups: Hanging(), history: SmileySearchHistoryStore(persistence: InMemorySmallStorePersistence())
        )
        let picker = SmileyPickerModel(
            catalogue: [], store: AppSmileyFavoritesStore(persistence: InMemorySmallStorePersistence()), account: "user1",
            search: search
        )
        let (window, host) = try window(SmileyPickerView(model: picker, onInsert: { _ in }), scheme: scheme)
        _ = host
        search.text = "miaou"
        search.submit(requireAll: false)
        try await settle(window)
        #expect(search.isSearching)
        return (window, classes(of: window))
    }

    /// The panel adds one glass view to the sheet (a material adds none: the buttons of the bar are the only other glass).
    @Test(arguments: [ColorScheme.light, .dark])
    func theTopicSearchProgressPanelIsGlass(scheme: ColorScheme) async throws {
        let (idleWindow, idle) = try await topicSheet(scheme: scheme, searching: false)
        idleWindow.isHidden = true
        let (window, searching) = try await topicSheet(scheme: scheme, searching: true)
        defer { window.isHidden = true }
        record(window, name: "topicsearch", scheme: scheme)
        let glass = "UIPlatformGlassInteractionView"
        #expect(searching.filter { $0 == glass }.count == idle.filter { $0 == glass }.count + 1)
    }

    /// The options strip is a system bottom bar (a scroll-edge pocket bar), not an inset with a `.bar` fill.
    @Test(arguments: [ColorScheme.light, .dark])
    func theSmileySearchOptionsAreASystemBottomBar(scheme: ColorScheme) async throws {
        let (window, names) = try await smileySheet(scheme: scheme)
        defer { window.isHidden = true }
        record(window, name: "smiley", scheme: scheme)
        #expect(names.contains { $0.contains("ScrollPocketBarInteraction") })
    }
}
