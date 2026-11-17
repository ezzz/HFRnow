import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// The presenter left to the app's rule (no forced placement) with « Composer moderne » off (#904), as by default (#855): the
/// reader's composer is presented, never the docked bar; full screen on an iPhone (legacy's cover), a sheet on an iPad.
@MainActor
@Suite(.serialized)
struct ComposerPlacementSwitchHostedTests {
    /// `explicit`: the switch set off in the settings, or left at its default.
    @Test(arguments: [true, false])
    func withTheModernComposerOffTheReaderShowsLegacysPresentation(explicit: Bool) async throws {
        let settings = ExperimentalSettings(store: InMemorySettingsStore())
        if explicit { settings.set(.modernComposer, isOn: false) }
        let state = SwitchState(ComposerFixture.model(poster: ScriptedPoster([])))
        let host = UIHostingController(rootView: SwitchHost(state: state).environment(settings))
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<100 where host.presentedViewController == nil { try await Task.sleep(for: .milliseconds(20)) }
        let presented = try #require(host.presentedViewController, "presented")
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        #expect(presented.modalPresentationStyle.coversTheScreen == isPhone, "\(presented.modalPresentationStyle.rawValue)")
        #expect(state.docked == nil, "the page sees no docked composer")
    }
}

@MainActor
@Observable
private final class SwitchState {
    var composer: ReplyComposerModel?
    var docked: DockedComposer?
    init(_ composer: ReplyComposerModel?) { self.composer = composer }
}

/// The reader's presenter with no forced placement; the page reports what it sees of the composer.
private struct SwitchHost: View {
    @Bindable var state: SwitchState

    var body: some View {
        DockedReader(state: state).modifier(ReaderComposerPresenter(composer: $state.composer) { _, _ in })
    }
}

private struct DockedReader: View {
    let state: SwitchState
    @Environment(\.dockedComposer) private var docked

    var body: some View {
        Color.gray.onChange(of: docked, initial: true) { _, value in state.docked = value }
    }
}

extension UIModalPresentationStyle {
    /// A full-screen cover: UIKit's `.fullScreen` (legacy's `coverVerticalFullScreen`, `MessagesView.swift:6019-6120` @ 87fe0d1c)
    /// or `.overFullScreen`, which SwiftUI's `fullScreenCover` uses (measured on the iOS 27.0 simulator, CI run of #985). Either
    /// one covers the whole screen; a sheet (`.pageSheet`, `.formSheet`) does not.
    var coversTheScreen: Bool { self == .fullScreen || self == .overFullScreen }
}
