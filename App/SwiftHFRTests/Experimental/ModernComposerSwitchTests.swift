import HFRStorage
import SwiftUI
@testable import SwiftHFR
import Testing
import UIKit

/// Réglages › Expérimental › « Composer moderne » (#903, #904): on, an iPhone's composer is the docked card (#653, #888); off, it
/// is the full-height sheet with legacy's bar and row, as on an iPad.
@MainActor
struct ModernComposerSwitchTests {
    @Test func theModernComposerIsAnIPhoneWithTheOptionOn() {
        #expect(ModernComposer.isActive(isPhone: true, isOn: true))
        #expect(!ModernComposer.isActive(isPhone: true, isOn: false))
        #expect(!ModernComposer.isActive(isPhone: false, isOn: true))
        #expect(!ModernComposer.isActive(isPhone: false, isOn: false))
    }

    /// Off: no partial height, no toggle, legacy's bar and row under the card. On: the docked card's.
    @Test(arguments: [true, false])
    func bothPathsOfTheSwitch(isOn: Bool) {
        let modern = ModernComposer.isActive(isPhone: true, isOn: isOn)
        #expect(ComposerHeight.offersToggle(isPhone: modern, verticalSizeClass: .regular) == isOn)
        #expect(ComposerHeight.shown(chosen: nil, isPhone: modern, verticalSizeClass: .regular) == (isOn ? .partial : .full))
        // A height chosen before the switch was turned off does not bring the card back.
        #expect(ComposerHeight.shown(chosen: .partial, isPhone: modern, verticalSizeClass: .regular) == (isOn ? .partial : .full))
        let chrome = ComposerChrome(isPhone: modern)
        #expect(chrome == (isOn ? .docked : .sheet))
        #expect(chrome.controlsInCard == isOn)
        #expect(chrome.headerFloats == isOn)
    }
}

@MainActor
private final class SwitchProbeBox {
    var frames: [ComposerLayoutProbe.Part: CGRect] = [:]

    var probe: ComposerLayoutProbe {
        ComposerLayoutProbe(frame: { [weak self] part, frame in self?.frames[part] = frame }, layout: { _ in })
    }
}

/// The real reply composer hosted in an iPhone-sized window with the switch on and off, its parts read through
/// `ComposerLayoutProbe` (as `ComposerLayoutHostedTests`, which runs with the switch on).
@MainActor
@Suite(.serialized)
struct ModernComposerSwitchHostedTests {
    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    private func host(modernComposer: Bool) async throws -> SwitchProbeBox {
        let box = SwitchProbeBox()
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let settings = ExperimentalSettings(store: InMemorySettingsStore())
        settings.set(.modernComposer, isOn: modernComposer)
        let model = ComposerFixture.model(poster: ScriptedPoster([]))
        let view = ReplyComposerView(model: model) { _ in }
            .environment(settings)
            .environment(\.composerLayoutProbe, box.probe)
            .appTypography(TextScale(percent: 100), density: .regular)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = UIHostingController(rootView: view)
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<100 where !model.canEdit { try await Task.sleep(for: .milliseconds(50)) }
        model.update(text: "Bonjour")
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            if box.frames[.controls] != nil, box.frames[.card] != nil { break }
        }
        try await Task.sleep(for: .milliseconds(300))
        return box
    }

    /// On an iPhone the control row is inside the card with the switch on, under it with the switch off; an iPad keeps it
    /// under the card either way.
    @Test(arguments: [true, false])
    func theControlRowFollowsTheSwitch(modernComposer: Bool) async throws {
        let box = try await host(modernComposer: modernComposer)
        let card = try #require(box.frames[.card])
        let controls = try #require(box.frames[.controls])
        if isPhone && modernComposer {
            #expect(card.insetBy(dx: -0.5, dy: -0.5).contains(controls), "card \(card), controls \(controls)")
        } else {
            #expect(controls.minY >= card.maxY - 0.5, "card \(card), controls \(controls)")
        }
    }
}
