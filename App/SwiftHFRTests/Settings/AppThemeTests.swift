import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// The app root's theme (LOT-121) in a real window: a manual theme overrides iOS for every view below the root (the reader's
/// web view reads the same trait), and going back to "Automatique (iOS)" follows iOS again without a relaunch.
@MainActor
@Suite(.serialized)
struct AppThemeTests {
    /// A UIKit view inside the SwiftUI tree, as the reader's `WKWebView` is.
    private final class Probe: UIView {}

    private struct ProbeView: UIViewRepresentable {
        let probe: Probe
        func makeUIView(context: Context) -> Probe { probe }
        func updateUIView(_ uiView: Probe, context: Context) {}
    }

    /// The root as the app builds it: `appTheme` is called from a `body`, so a change of the model updates it.
    private struct Root: View {
        let model: ThemeSettingsModel
        let probe: Probe
        var body: some View { ProbeView(probe: probe).appTheme(model) }
    }

    private func until(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    @Test func aManualThemeOverridesIOSThenAutomaticFollowsItAgainLive() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        // Distinct accents: red in light, blue in dark.
        let model = ThemeSettingsModel(store: InMemorySettingsStore([
            "theme_day_color_action": .string("{1.000, 0.000, 0.000, 1.000}"),
            "theme_night_color_action": .string("{0.000, 0.000, 1.000, 1.000}")
        ]))
        let probe = Probe()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        window.rootViewController = UIHostingController(rootView: Root(model: model, probe: probe))
        window.isHidden = false
        defer { window.isHidden = true }
        let system = window.traitCollection.userInterfaceStyle
        let other: ThemeSettingsModel.Mode = system == .dark ? .light : .dark
        let otherStyle: UIUserInterfaceStyle = other == .dark ? .dark : .light

        #expect(await until { probe.window != nil && probe.traitCollection.userInterfaceStyle == system })
        // UIKit chrome (alerts) reads the window's tint: the accent of the variant shown.
        func tintIsAccent() -> Bool {
            let dark = window.traitCollection.userInterfaceStyle == .dark
            let accent = UIColor(red: dark ? 0 : 1, green: 0, blue: dark ? 1 : 0, alpha: 1)
            return window.tintColor?.resolvedColor(with: window.traitCollection).isEqual(accent) == true
        }
        #expect(await until { tintIsAccent() }, "tint at the system style")
        model.mode = other
        #expect(await until { probe.traitCollection.userInterfaceStyle == otherStyle }, "manual theme not applied")
        #expect(await until { tintIsAccent() }, "tint after the switch")
        model.mode = .system
        #expect(await until { probe.traitCollection.userInterfaceStyle == system }, "automatic theme did not follow iOS again")
    }

    /// A real window with a navigation stack and a list: the dark style paints the screen, light mode and "standard" do not.
    private struct ListRoot: View {
        let model: ThemeSettingsModel
        /// Shows a pushed screen (which carries no modifier of its own) instead of the root.
        var pushed = false
        @State private var path: [Int] = []
        var body: some View {
            NavigationStack(path: $path) {
                List { Text("") }.appScreenBackground()
                    .navigationDestination(for: Int.self) { _ in List { Text("") }.appScreenBackground() }
            }
            .appTheme(model)
            .onAppear { if pushed { path = [1] } }
        }
    }

    /// The colour of a pixel near the bottom of the window, below the one list row.
    private func bottomPixel(of window: UIWindow) -> (red: Int, green: Int, blue: Int) {
        let size = window.bounds.size
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        let scale = image.scale
        if let cgImage = image.cgImage {
            // Bottom-left origin: put the pixel 20 pt above the bottom edge, in the middle, on the 1 x 1 canvas.
            let canvas = CGRect(
                x: -size.width * scale / 2, y: -20 * scale, width: size.width * scale, height: size.height * scale
            )
            context?.draw(cgImage, in: canvas)
        }
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    @Test func theDarkerStylePaintsTheScreenBehindAListAndLightModeIsUntouched() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let store = InMemorySettingsStore(["auto_theme": .int(0), "theme": .int(1), "theme_dark_style": .int(1)])
        let model = ThemeSettingsModel(store: store)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 300, height: 600)
        window.rootViewController = UIHostingController(rootView: ListRoot(model: model))
        window.isHidden = false
        defer { window.isHidden = true }

        func darkIs(_ expected: Int) async -> Bool {
            await until { window.traitCollection.userInterfaceStyle == .dark && bottomPixel(of: window).red == expected }
        }
        #expect(await darkIs(11), "darker: \(bottomPixel(of: window))")
        model.darkStyle = .standard
        #expect(await darkIs(0), "standard: \(bottomPixel(of: window))")
        model.darkStyle = .oled
        #expect(await darkIs(0), "oled: \(bottomPixel(of: window))")
        model.darkStyle = .darker
        model.mode = .light
        // Light: the system's grouped-list grey, not the dark style's.
        #expect(await until { window.traitCollection.userInterfaceStyle == .light && bottomPixel(of: window).red > 200 })
    }

    /// A screen pushed on a container whose root carries `appScreenBackground()` shows the same background.
    @Test func aPushedScreenKeepsTheDarkBackground() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let model = ThemeSettingsModel(store: InMemorySettingsStore(["auto_theme": .int(0), "theme": .int(1), "theme_dark_style": .int(1)]))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 300, height: 600)
        window.rootViewController = UIHostingController(rootView: ListRoot(model: model, pushed: true))
        window.isHidden = false
        defer { window.isHidden = true }
        let shown = await until { bottomPixel(of: window).red == 11 }
        #expect(shown, "pushed: \(bottomPixel(of: window))")
    }
}
