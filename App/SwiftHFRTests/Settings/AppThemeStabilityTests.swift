import HFRModels
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// What `appScreenBackground()` must not do (LOT-122): rebuild the screen below it when the style or the appearance flips, or
/// change anything when the style is off. Real windows, measured against counted views and against control screens.
extension AppThemeTests {
    /// A model on the manual theme `mode` (0 light, 1 dark) and dark style `style` (0 standard, 1 darker, 2 OLED).
    private func themeModel(mode: Int, style: Int) -> ThemeSettingsModel {
        ThemeSettingsModel(store: InMemorySettingsStore(["auto_theme": .int(0), "theme": .int(mode), "theme_dark_style": .int(style)]))
    }

    /// A scene's window with `root` in it, shown; the caller hides it.
    private func show(_ root: some View, size: CGSize) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = UIHostingController(rootView: root)
        window.isHidden = false
        return window
    }

    /// The RGB of a 6 x 8 grid of pixels over the window: the whole screen, not one point.
    private func samples(of window: UIWindow) -> [[Int]] {
        let size = window.bounds.size
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let cgImage = image.cgImage else { return [] }
        let scale = image.scale
        return (0..<48).map { index in
            var data = [UInt8](repeating: 0, count: 4)
            let context = CGContext(
                data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            let x = (CGFloat(index % 6) + 0.5) * size.width / 6, y = (CGFloat(index / 6) + 0.5) * size.height / 8
            // Bottom-left origin.
            context?.draw(cgImage, in: CGRect(
                x: -x * scale, y: -(size.height - y) * scale, width: size.width * scale, height: size.height * scale
            ))
            return data.prefix(3).map(Int.init)
        }
    }

    // MARK: Identity

    /// Counts the UIKit views SwiftUI makes: the reader's web view, a composer's editor or a list's state, rebuilt, would count again.
    private final class Counter { var made = 0 }

    private struct CountingView: UIViewRepresentable {
        let counter: Counter
        func makeUIView(context: Context) -> UIView {
            counter.made += 1
            return UIView()
        }
        func updateUIView(_ uiView: UIView, context: Context) {}
    }

    /// A counting view as the root of a stack (themed, or the plain `NavigationStack` for the control).
    private struct StackRoot: View {
        let model: ThemeSettingsModel
        let counter: Counter
        var themed = true
        var body: some View {
            Group {
                if themed {
                    ThemedNavigationStack { CountingView(counter: counter) }
                } else {
                    NavigationStack { CountingView(counter: counter) }
                }
            }
            .appTheme(model)
        }
    }

    /// The iPad layout: a counting view as the detail column (the reader), lists in the others.
    private struct CountingSplitRoot: View {
        let model: ThemeSettingsModel
        let counter: Counter
        var body: some View {
            NavigationSplitView(columnVisibility: .constant(.all)) {
                List { Text("") }.appScreenBackground()
            } content: {
                List { Text("") }.appScreenBackground()
            } detail: {
                CountingView(counter: counter).appScreenBackground()
            }
            .appTheme(model)
        }
    }

    /// Flips dark, light, dark and Darker, Standard, Darker, OLED under a themed stack and a split column: the state below
    /// `appScreenBackground()` must survive. On 76ded38f (the modifier's `if`/`else`) this made 2 views at the first dark, 4 after
    /// the appearance round trip and 6 after the style flips, in both layouts.
    @Test(arguments: ["stack", "split"])
    func flippingTheAppearanceOrTheStyleKeepsTheStateBelowTheModifier(kind: String) async throws {
        let model = themeModel(mode: 1, style: 1)
        let counter = Counter()
        let size = CGSize(width: 1100, height: 700)
        let window = kind == "stack"
            ? try show(StackRoot(model: model, counter: counter), size: size)
            : try show(CountingSplitRoot(model: model, counter: counter), size: size)
        defer { window.isHidden = true }
        func settle(_ style: UIUserInterfaceStyle) async {
            _ = await until { window.traitCollection.userInterfaceStyle == style }
            for _ in 0..<5 {
                _ = samples(of: window)
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
        await settle(.dark)
        #expect(counter.made == 1, "\(kind): shown, made \(counter.made)")
        model.mode = .light
        await settle(.light)
        model.mode = .dark
        await settle(.dark)
        #expect(counter.made == 1, "\(kind): dark, light, dark made \(counter.made)")
        for style in [DarkStyle.standard, .darker, .oled] {
            model.darkStyle = style
            await settle(.dark)
        }
        #expect(counter.made == 1, "\(kind): after the style flips made \(counter.made)")
    }

    // MARK: Pixel identity with the style off

    /// Three columns as the iPad layout builds them: two lists and a screen that is not a list.
    private struct SplitControlRoot: View {
        let model: ThemeSettingsModel
        var themed = true
        var body: some View {
            NavigationSplitView(columnVisibility: .constant(.all)) {
                List { Text("") }.screenBackground(themed)
            } content: {
                List { Text("") }.screenBackground(themed)
            } detail: {
                Text("").frame(maxWidth: .infinity, maxHeight: .infinity).screenBackground(themed)
            }
            .appTheme(model)
        }
    }

    private func shot(_ root: some View, style: UIUserInterfaceStyle) async throws -> [[Int]] {
        let window = try show(root, size: CGSize(width: 1100, height: 700))
        defer { window.isHidden = true }
        _ = await until { window.traitCollection.userInterfaceStyle == style }
        try? await Task.sleep(for: .milliseconds(400))
        _ = samples(of: window)
        try? await Task.sleep(for: .milliseconds(200))
        return samples(of: window)
    }

    /// With the style off (Standard in dark, any style in light) a screen looks exactly as it does without the modifier, pixel
    /// for pixel over the whole window: a list screen, a screen that is not a list, and the three columns of a split view (the
    /// iPad sidebar's material included).
    @Test(arguments: [(1, 0, UIUserInterfaceStyle.dark), (0, 0, .light), (0, 1, .light), (0, 2, .light)])
    func withTheStyleOffAScreenIsPixelIdenticalToOneWithoutTheModifier(mode: Int, style: Int, ui: UIUserInterfaceStyle) async throws {
        let name = "mode \(mode) style \(style)"
        let model = { self.themeModel(mode: mode, style: style) }
        let list = try await shot(ListRoot(model: model()), style: ui)
        let listControl = try await shot(ListRoot(model: model(), themed: false), style: ui)
        #expect(list == listControl, "list, \(name)")
        let plain = try await shot(StackRoot(model: model(), counter: Counter()), style: ui)
        let plainControl = try await shot(StackRoot(model: model(), counter: Counter(), themed: false), style: ui)
        #expect(plain == plainControl, "screen without list, \(name)")
        let split = try await shot(SplitControlRoot(model: model()), style: ui)
        let splitControl = try await shot(SplitControlRoot(model: model(), themed: false), style: ui)
        #expect(split == splitControl, "split view, \(name)")
    }

    /// The control above can fail: with the style on in dark, the same screens differ from the system's.
    @Test func withTheStyleOnAScreenDiffersFromOneWithoutTheModifier() async throws {
        let list = try await shot(ListRoot(model: themeModel(mode: 1, style: 1)), style: .dark)
        let listControl = try await shot(ListRoot(model: themeModel(mode: 1, style: 1), themed: false), style: .dark)
        #expect(list != listControl, "the darker style changed nothing on a list")
        let plain = try await shot(StackRoot(model: themeModel(mode: 1, style: 1), counter: Counter()), style: .dark)
        let plainControl = try await shot(StackRoot(model: themeModel(mode: 1, style: 1), counter: Counter(), themed: false), style: .dark)
        #expect(plain != plainControl, "the darker style changed nothing on a screen without list")
        let split = try await shot(SplitControlRoot(model: themeModel(mode: 1, style: 1)), style: .dark)
        let splitControl = try await shot(SplitControlRoot(model: themeModel(mode: 1, style: 1), themed: false), style: .dark)
        #expect(split != splitControl, "the darker style changed nothing on a split view")
    }

    // MARK: Compact width and unthemed pushes

    /// The collapsed split views of the iPhone layouts (`CategoriesTabView`, `FavoritesTabView`, `MessagesRootView`): the column
    /// shown carries the style. Needs a compact-width window.
    @Test func aCollapsedSplitViewShowsTheDarkStyle() async throws {
        let model = themeModel(mode: 1, style: 1)
        let window = try show(SplitRoot(model: model), size: CGSize(width: 320, height: 600))
        defer { window.isHidden = true }
        let compact = await until { window.rootViewController?.traitCollection.horizontalSizeClass == .compact }
        try #require(compact, "this window is not compact-width")
        let shown = await until { window.traitCollection.userInterfaceStyle == .dark && pixel(of: window, x: 160) == 11 }
        #expect(shown, "collapsed split view: \(pixel(of: window, x: 160))")
        model.darkStyle = .oled
        #expect(await until { pixel(of: window, x: 160) == 0 }, "oled: \(pixel(of: window, x: 160))")
    }

    /// A screen pushed without the modifier keeps the system fill: the modifier of the root does not paint it.
    @Test func aScreenPushedWithoutTheModifierKeepsTheSystemFill() async throws {
        let root = ListRoot(model: themeModel(mode: 1, style: 1), pushed: true, pushedThemed: false)
        let window = try show(root, size: CGSize(width: 300, height: 600))
        defer { window.isHidden = true }
        #expect(await until { pixel(of: window, x: 150, y: 350) == 255 }, "pushed screen not shown")
        let bottom = bottomPixel(of: window)[0]
        #expect(bottom == 0, "system fill in dark, not the darker style's: \(bottom)")
    }
}
