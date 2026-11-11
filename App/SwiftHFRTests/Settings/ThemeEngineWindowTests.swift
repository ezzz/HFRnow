import HFRModels
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// A gallery theme in real windows (LOT-188): the fixture theme recolours a list, a pushed screen, every split column and a
/// sheet, in light and dark, and an appearance flip rebuilds nothing below `appScreenBackground()`.
@MainActor
@Suite(.serialized)
struct ThemeEngineWindowTests {
    /// The fixture theme's background red channel: #E6EEF8 in light, #101820 in dark.
    static let lightRed = 0xE6
    static let darkRed = 0x10

    func themedModel(dark: Bool) throws -> ThemeSettingsModel {
        let catalog = try ThemeFixtures.catalog()
        let model = ThemeSettingsModel(store: InMemorySettingsStore(["auto_theme": .int(0), "theme": .int(dark ? 1 : 0)]), catalog: catalog)
        model.select(try #require(catalog.themes.first { $0.id == "test-theme" }))
        return model
    }

    func until(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    func show(_ root: some View, size: CGSize) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = UIHostingController(rootView: root)
        window.isHidden = false
        return window
    }

    /// The red channel at `x`, `y` pt above the bottom of the window.
    func red(in window: UIWindow, x: CGFloat, y: CGFloat = 20) -> Int {
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        if let cgImage = image.cgImage {
            let scale = image.scale
            context?.draw(cgImage, in: CGRect(
                x: -x * scale, y: -y * scale, width: window.bounds.width * scale, height: window.bounds.height * scale
            ))
        }
        return Int(data[0])
    }

    /// A list in a themed stack, optionally with a pushed list (a red band marks it) or a sheet holding a themed stack.
    struct StackRoot: View {
        let model: ThemeSettingsModel
        var pushed = false
        var sheet = false
        @State private var path: [Int] = []
        @State private var showsSheet = false
        var body: some View {
            // A stack with a path, its root carrying the modifier as `ThemedNavigationStack` does.
            NavigationStack(path: $path) {
                List { Text("") }
                    .appScreenBackground()
                    .navigationDestination(for: Int.self) { _ in
                        List { Text("") }.overlay(alignment: .top) { Color.red.frame(height: 400) }.appScreenBackground()
                    }
            }
            .sheet(isPresented: $showsSheet) {
                ThemedNavigationStack { List { Text("") }.overlay(alignment: .top) { Color.red.frame(height: 400) } }
                    .presentationDetents([.large])
            }
            .appTheme(model)
            .onAppear {
                if pushed { path = [1] }
                if sheet { showsSheet = true }
            }
        }
    }

    @Test(arguments: [false, true])
    func theThemePaintsTheScreenBehindAList(dark: Bool) async throws {
        let model = try themedModel(dark: dark)
        let window = try show(StackRoot(model: model), size: CGSize(width: 300, height: 600))
        defer { window.isHidden = true }
        let expected = dark ? Self.darkRed : Self.lightRed
        #expect(await until { red(in: window, x: 150) == expected }, "list: \(red(in: window, x: 150))")
        // Back to Legacy: the system's grouped background again (light #F2F2F7, dark #000000).
        model.select(model.catalog.themes[0])
        #expect(await until { red(in: window, x: 150) == (dark ? 0 : 0xF2) }, "legacy: \(red(in: window, x: 150))")
    }

    @Test func aPushedScreenShowsTheTheme() async throws {
        let model = try themedModel(dark: true)
        let window = try show(StackRoot(model: model, pushed: true), size: CGSize(width: 300, height: 600))
        defer { window.isHidden = true }
        #expect(await until { red(in: window, x: 150, y: 350) == 255 }, "pushed screen not shown")
        #expect(await until { red(in: window, x: 150) == Self.darkRed }, "pushed: \(red(in: window, x: 150))")
    }

    @Test func aSheetShowsTheTheme() async throws {
        let model = try themedModel(dark: true)
        let window = try show(StackRoot(model: model, sheet: true), size: CGSize(width: 300, height: 600))
        defer { window.isHidden = true }
        #expect(await until { red(in: window, x: 150, y: 350) == 255 }, "sheet not shown")
        #expect(await until { red(in: window, x: 150) == Self.darkRed }, "sheet: \(red(in: window, x: 150))")
    }

    struct SplitRoot: View {
        let model: ThemeSettingsModel
        var body: some View {
            NavigationSplitView(columnVisibility: .constant(.all)) {
                List { Text("") }.appScreenBackground()
            } content: {
                List { Text("") }.appScreenBackground()
            } detail: {
                List { Text("") }.appScreenBackground()
            }
            .appTheme(model)
        }
    }

    @Test(arguments: [false, true])
    func everySplitColumnShowsTheTheme(dark: Bool) async throws {
        let model = try themedModel(dark: dark)
        let window = try show(SplitRoot(model: model), size: CGSize(width: 1100, height: 700))
        defer { window.isHidden = true }
        let columnXs: [CGFloat] = [60, 500, 900]
        let expected = dark ? Self.darkRed : Self.lightRed
        let shown = await until { columnXs.allSatisfy { red(in: window, x: $0) == expected } }
        #expect(shown, "columns: \(columnXs.map { red(in: window, x: $0) })")
    }

    // MARK: Identity

    final class Counter { var made = 0 }

    struct CountingView: UIViewRepresentable {
        let counter: Counter
        func makeUIView(context: Context) -> UIView {
            counter.made += 1
            return UIView()
        }
        func updateUIView(_ uiView: UIView, context: Context) {}
    }

    /// The root as the app builds it: `appTheme` is called from a `body`, so a change of the model reaches the window.
    struct CountingRoot: View {
        let model: ThemeSettingsModel
        let counter: Counter
        var split = false
        var body: some View {
            Group {
                if split {
                    NavigationSplitView(columnVisibility: .constant(.all)) {
                        List { Text("") }.appScreenBackground()
                    } content: {
                        List { Text("") }.appScreenBackground()
                    } detail: {
                        CountingView(counter: counter).appScreenBackground()
                    }
                } else {
                    ThemedNavigationStack { CountingView(counter: counter) }
                }
            }
            .appTheme(model)
        }
    }

    /// Dark, light, dark under a themed stack and under a split column: the counted view is made once, and each flip is seen
    /// (the window's style and the theme's background pixel). A change of theme may rebuild (the user's own change), a flip
    /// may not (LOT-122's rule, kept by LOT-188).
    @Test(arguments: [false, true])
    func flippingTheAppearanceUnderAThemeRebuildsNothing(split: Bool) async throws {
        let model = try themedModel(dark: true)
        let counter = Counter()
        let size = split ? CGSize(width: 1100, height: 700) : CGSize(width: 400, height: 600)
        let window = try show(CountingRoot(model: model, counter: counter, split: split), size: size)
        defer { window.isHidden = true }
        // A list column (split) or nothing over the stack's background: either shows the theme's fill.
        let x: CGFloat = split ? 60 : 200
        #expect(await until { window.traitCollection.userInterfaceStyle == .dark && red(in: window, x: x) == Self.darkRed })
        #expect(counter.made == 1, "shown, made \(counter.made)")
        for mode in [ThemeSettingsModel.Mode.light, .dark] {
            model.mode = mode
            let style: UIUserInterfaceStyle = mode == .dark ? .dark : .light
            let expected = mode == .dark ? Self.darkRed : Self.lightRed
            let flipped = await until { window.traitCollection.userInterfaceStyle == style && red(in: window, x: x) == expected }
            #expect(flipped, "\(mode): \(red(in: window, x: x))")
            for _ in 0..<5 {
                _ = red(in: window, x: x)
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
        #expect(counter.made == 1, "split \(split): made \(counter.made)")
    }
}
