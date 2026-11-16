import SwiftUI
import UIKit

// Port of Classes/HFRplusAppDelegate.m (applicationDidBecomeActive, the alert `:665-676`) @ 87fe0d1c. Differences (GAP-147):
// the operator's text and its « Désactiver » instead of legacy's one-button « C'est bientôt Noël ! »; shown only on a clear
// screen and by one scene; kept until answered, across launches.
/// The arrival alert of one scene: it asks the model every second while an arrival is pending, and presents it once the lock,
/// any sheet or alert and the keyboard are gone and no other scene shows it.
struct SeasonalArrivalAlert: ViewModifier {
    let model: SeasonalThemeModel
    let isCovered: @MainActor () -> Bool
    @State private var scene = UUID()
    @State private var shown: SeasonalThemeModel.Alert?
    @State private var keyboardVisible = false
    @State private var window = WindowReference()

    func body(content: Content) -> some View {
        content
            .background(WindowReader(reference: window))
            // A normal alert, spoken by VoiceOver (THEMES.md §4 rule 6). The setter ignores the dismissal: each button answers.
            .alert("Oh Oh Oh !", isPresented: Binding(get: { shown != nil }, set: { _ in }), presenting: shown) { _ in
                Button("OK") { answer(disable: false) }
                Button("Désactiver") { answer(disable: true) }
            } message: { _ in
                Text("Thème disponible dans les réglages")
            }
            .task(id: model.pendingAlert) {
                while !Task.isCancelled, model.pendingAlert != nil, shown == nil {
                    let screen = SeasonalThemeModel.ScreenState(
                        isCovered: isCovered(), isPresenting: window.isPresenting, isKeyboardVisible: keyboardVisible
                    )
                    if let alert = model.alert(for: scene, screen: screen) {
                        shown = alert
                    } else {
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
            }
            .onChange(of: model.pendingAlert) { _, pending in
                if pending == nil { shown = nil }
            }
            .task {
                for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardDidShowNotification) {
                    keyboardVisible = true
                }
            }
            .task {
                for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardDidHideNotification) {
                    keyboardVisible = false
                }
            }
            .onDisappear { model.releaseAlert(for: scene) }
    }

    private func answer(disable: Bool) {
        shown = nil
        model.answerArrival(disable: disable)
    }
}

/// The window a view is in, read without keeping it alive.
@MainActor
final class WindowReference {
    weak var window: UIWindow?

    /// Something is presented over the window's root: a sheet, the composer, a cover or an alert.
    var isPresenting: Bool { window?.rootViewController?.presentedViewController != nil }
}

/// Hands its window to `reference` once it is in one.
struct WindowReader: UIViewRepresentable {
    let reference: WindowReference

    final class Probe: UIView {
        var reference: WindowReference?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            reference?.window = window
        }
    }

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        probe.reference = reference
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.reference = reference
        reference.window = probe.window
    }
}
