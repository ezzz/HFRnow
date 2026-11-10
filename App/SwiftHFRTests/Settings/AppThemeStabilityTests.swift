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
    private func show(_ root: some View, size: CGSize, host: UIColor? = nil) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        let hosting = UIHostingController(rootView: root)
        // Not `systemBackground`: a screen that stops painting its own fill shows this through.
        hosting.view.backgroundColor = host
        window.rootViewController = hosting
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

    /// Flips dark, light, dark (and Darker, OLED, Darker) under a themed stack and a split column: the state below
    /// `appScreenBackground()` must survive an iOS appearance switch, which the user does not control. On 76ded38f and d66cf402
    /// (an `if`/`else` on the appearance, then an empty builder) the first made 2 views at the first dark, 4 after the round trip,
    /// 6 after the style flips; the second 1. A change from or to Standard rebuilds (the user's own change in Settings): not asserted.
    @Test(arguments: ["stack", "split"], [0, 1])
    func flippingTheAppearanceKeepsTheStateBelowTheModifier(kind: String, style: Int) async throws {
        let model = themeModel(mode: 1, style: style)
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
        for _ in 0..<2 {
            model.mode = .light
            await settle(.light)
            model.mode = .dark
            await settle(.dark)
        }
        #expect(counter.made == 1, "\(kind): dark, light, dark made \(counter.made)")
        if style != 0 {
            // Darker and OLED share one structure.
            for style in [DarkStyle.oled, .darker] {
                model.darkStyle = style
                await settle(.dark)
            }
            #expect(counter.made == 1, "\(kind): Darker, OLED, Darker made \(counter.made)")
        }
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

    /// A stack that has pushed a screen that is not a list (a loading or an empty state).
    private struct PushedPlainRoot: View {
        let model: ThemeSettingsModel
        var themed = true
        @State private var path = [1]
        var body: some View {
            NavigationStack(path: $path) {
                List { Text("") }.screenBackground(themed)
                    .navigationDestination(for: Int.self) { _ in
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).screenBackground(themed)
                    }
            }
            .appTheme(model)
        }
    }

    /// A medium sheet holding a stack with a screen that is not a list.
    private struct SheetRoot: View {
        let model: ThemeSettingsModel
        var themed = true
        var body: some View {
            Color.clear
                .sheet(isPresented: .constant(true)) {
                    Group {
                        if themed {
                            ThemedNavigationStack { ProgressView() }
                        } else {
                            NavigationStack { ProgressView() }
                        }
                    }
                    .presentationDetents([.medium])
                }
                .appTheme(model)
        }
    }

    /// Every kind of container the modifier is applied to; `themed: false` is the control without the modifier.
    nonisolated static let kinds = ["list", "plain", "split", "pushed", "sheet"]

    /// A theme setting that leaves the system's screens alone (Standard): `mode` 0 light, 1 dark; `style` 0 standard, 1 darker, 2 OLED.
    struct StyleOff: Sendable {
        let mode: Int, style: Int, scheme: UIUserInterfaceStyle
        static let all = [StyleOff(mode: 1, style: 0, scheme: .dark), StyleOff(mode: 0, style: 0, scheme: .light)]
    }

    private func screen(_ kind: String, _ model: ThemeSettingsModel, themed: Bool) -> AnyView {
        switch kind {
        case "list": AnyView(ListRoot(model: model, themed: themed))
        case "plain": AnyView(StackRoot(model: model, counter: Counter(), themed: themed))
        case "split": AnyView(SplitControlRoot(model: model, themed: themed))
        case "pushed": AnyView(PushedPlainRoot(model: model, themed: themed))
        default: AnyView(SheetRoot(model: model, themed: themed))
        }
    }

    /// The window over a red host view, settled: a container that stops painting its fill shows the red.
    private func shot(_ root: some View, style: UIUserInterfaceStyle) async throws -> [[Int]] {
        let window = try show(root, size: CGSize(width: 1100, height: 700), host: .red)
        defer { window.isHidden = true }
        _ = await until { window.traitCollection.userInterfaceStyle == style }
        try? await Task.sleep(for: .milliseconds(600))
        _ = samples(of: window)
        try? await Task.sleep(for: .milliseconds(200))
        return samples(of: window)
    }

    /// With the style off (Standard) a screen looks exactly as it does without the modifier, pixel
    /// for pixel over the whole window, on every container: a list, a screen that is not a list, the three columns of a split
    /// view (the iPad sidebar's material included), a pushed screen that is not a list, a medium sheet. The host view behind is
    /// red, so a container whose fill went missing shows it.
    @Test(arguments: AppThemeTests.kinds, StyleOff.all)
    func withTheStyleOffAScreenIsPixelIdenticalToOneWithoutTheModifier(
        kind: String, setting: StyleOff
    ) async throws {
        let themed = try await shot(
            screen(kind, themeModel(mode: setting.mode, style: setting.style), themed: true), style: setting.scheme
        )
        let control = try await shot(
            screen(kind, themeModel(mode: setting.mode, style: setting.style), themed: false), style: setting.scheme
        )
        #expect(themed == control, "\(kind), mode \(setting.mode) style \(setting.style)")
    }

    /// The control above can fail: with the style on in dark, the same screens differ from the system's.
    @Test(arguments: AppThemeTests.kinds)
    func withTheStyleOnAScreenDiffersFromOneWithoutTheModifier(kind: String) async throws {
        let themed = try await shot(screen(kind, themeModel(mode: 1, style: 1), themed: true), style: .dark)
        let control = try await shot(screen(kind, themeModel(mode: 1, style: 1), themed: false), style: .dark)
        #expect(themed != control, "the darker style changed nothing on \(kind)")
    }

    /// In light the darker and OLED styles keep the system's background on the stacks (a list, a screen that is not a list, a
    /// pushed one), pixel for pixel; a split column and a sheet are not claimed (they lose their own fill, see the spec).
    @Test(arguments: ["list", "plain", "pushed"], [1, 2])
    func inLightADarkerStyleKeepsTheSystemBackgroundOnStacks(kind: String, style: Int) async throws {
        let themed = try await shot(screen(kind, themeModel(mode: 0, style: style), themed: true), style: .light)
        let control = try await shot(screen(kind, themeModel(mode: 0, style: style), themed: false), style: .light)
        #expect(themed == control, "\(kind), light, style \(style)")
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
