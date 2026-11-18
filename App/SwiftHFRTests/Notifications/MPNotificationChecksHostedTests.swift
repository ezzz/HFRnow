import HFRStorage
import Observation
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// #1060: the checks of Réglages › Notifications MP against iOS run on the real Réglages screen while the section is out of
/// sight (a lazy `Form` does not build its rows, review r1 on #1097).
@MainActor
@Suite(.serialized)
struct MPNotificationChecksHostedTests {
    /// The scene phase the hosted screen reads, so a test can take the app away and back.
    @MainActor
    @Observable
    final class Phase {
        var value: ScenePhase = .active
    }

    private struct Host: View {
        let model: MPNotificationSettingsModel
        let phase: Phase

        var body: some View {
            ThemedNavigationStack { SettingsView(store: InMemorySettingsStore(), notifications: model) }
                .environment(GeneralSettingsModel(store: InMemorySettingsStore()))
                .environment(ExperimentalSettings(store: InMemorySettingsStore()))
                .environment(ThemeSettingsModel(store: InMemorySettingsStore()))
                .environment(SeasonalThemeModel(store: InMemorySettingsStore()))
                .environment(AccountsModel.preview())
                .environment(AppLockModel.preview())
                .environment(\.scenePhase, phase.value)
        }
    }

    /// The pushed screen of `StackHost`, so a test can push one over Réglages and pop back.
    @MainActor
    @Observable
    final class Path {
        var screens: [Int] = []
        /// How many times the pushed screen appeared.
        var shown = 0
    }

    /// Réglages at the root of a stack the test drives, as Thème, Icône or Listes are pushed over it.
    private struct StackHost: View {
        let model: MPNotificationSettingsModel
        let path: Path

        var body: some View {
            @Bindable var path = path
            NavigationStack(path: $path.screens) {
                SettingsView(store: InMemorySettingsStore(), notifications: model)
                    .navigationDestination(for: Int.self) { _ in Text("Sous-écran").onAppear { path.shown += 1 } }
            }
            .environment(GeneralSettingsModel(store: InMemorySettingsStore()))
            .environment(ExperimentalSettings(store: InMemorySettingsStore()))
            .environment(ThemeSettingsModel(store: InMemorySettingsStore()))
            .environment(SeasonalThemeModel(store: InMemorySettingsStore()))
            .environment(AccountsModel.preview())
            .environment(AppLockModel.preview())
        }
    }

    private func model(_ permission: FakeNotificationPermission) -> MPNotificationSettingsModel {
        MPNotificationSettingsModel(
            store: InMemorySettingsStore(), ledger: NotificationLedgerStore(persistence: InMemorySmallStorePersistence()),
            reschedule: {}, permission: permission
        )
    }

    /// A window 300 points high: only the first rows of « Général » are built, Notifications MP is far below.
    private func host(_ view: some View) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 300)
        window.rootViewController = UIHostingController(rootView: view)
        window.isHidden = false
        window.rootViewController?.view.layoutIfNeeded()
        return window
    }

    private func close(_ window: UIWindow) {
        window.rootViewController?.dismiss(animated: false)
        window.isHidden = true
    }

    /// The controller the window presents, nil when nothing is presented.
    private func presented(in window: UIWindow) -> UIViewController? {
        var controller = window.rootViewController?.presentedViewController
        while let next = controller?.presentedViewController { controller = next }
        return controller
    }

    /// Waits up to 2 s for `condition`.
    private func wait(until condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func openingSettingsShowsTheAlertWithTheSectionOutOfSight() async throws {
        let permission = FakeNotificationPermission(.denied)
        let model = model(permission)
        let window = try host(Host(model: model, phase: Phase()))
        defer { close(window) }
        try await wait { presented(in: window) != nil }
        #expect(model.alert == .notifications)
        #expect(presented(in: window) != nil)
        #expect(await permission.reads >= 1)
    }

    @Test func comingBackToTheAppReadsIOSAgainWithTheSectionOutOfSight() async throws {
        let permission = FakeNotificationPermission(.allowed)
        let model = model(permission)
        let phase = Phase()
        let window = try host(Host(model: model, phase: phase))
        defer { close(window) }
        // The opening's read, which finds nothing to say.
        try await Task.sleep(for: .milliseconds(500))
        let opened = await permission.reads
        #expect(model.alert == nil)
        #expect(opened >= 1)
        await permission.change(to: .badgesOff)
        phase.value = .background
        try await Task.sleep(for: .milliseconds(100))
        phase.value = .active
        try await wait { presented(in: window) != nil }
        #expect(model.alert == .badge)
        #expect(await permission.reads > opened)
    }

    // Review r2 on #1097: a stack root's task can run again when a pushed screen pops; that is not a new opening of Réglages.
    @Test func poppingBackFromASubScreenDoesNotShowTheSameAlertAgain() async throws {
        let permission = FakeNotificationPermission(.denied)
        let model = model(permission)
        let path = Path()
        let window = try host(StackHost(model: model, path: path))
        defer { close(window) }
        try await wait { presented(in: window) != nil }
        #expect(model.alert == .notifications)
        // « Annuler ».
        model.alert = nil
        try await wait { presented(in: window) == nil }
        let before = await permission.reads
        path.screens = [1]
        try await wait { path.shown == 1 }
        #expect(path.shown == 1)
        try await Task.sleep(for: .milliseconds(300))
        path.screens = []
        for _ in 0..<50 where await permission.reads == before {
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(500))
        // Whether the root's task runs again on the pop is up to SwiftUI (on the iOS 27.0 simulator it does not, measured
        // 2026-11-18); either way the alert this opening already showed stays away (`appearingAgainIsNotAnOpening`).
        #expect(model.alert == nil)
        #expect(presented(in: window) == nil)
    }
}
