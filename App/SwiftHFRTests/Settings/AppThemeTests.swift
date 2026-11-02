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
        let model = ThemeSettingsModel(store: InMemorySettingsStore())
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
        // UIKit chrome (alerts) reads the window's tint: the accent.
        let tint = UIColor(model.appearance.accentColor).resolvedColor(with: window.traitCollection)
        #expect(await until { window.tintColor?.resolvedColor(with: window.traitCollection) == tint })
        model.mode = other
        #expect(await until { probe.traitCollection.userInterfaceStyle == otherStyle }, "manual theme not applied")
        model.mode = .system
        #expect(await until { probe.traitCollection.userInterfaceStyle == system }, "automatic theme did not follow iOS again")
    }
}
