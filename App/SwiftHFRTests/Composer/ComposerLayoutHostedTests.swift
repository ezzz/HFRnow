import SwiftUI
@testable import SwiftHFR
import Testing
import UIKit

@MainActor
private final class ProbeBox {
    var frames: [ComposerLayoutProbe.Part: CGRect] = [:]
    var layout = ComposerCardLayout()

    var probe: ComposerLayoutProbe {
        ComposerLayoutProbe(frame: { [weak self] part, frame in self?.frames[part] = frame }, layout: { [weak self] in self?.layout = $0 })
    }
}

/// The real reply composer hosted in a 402 × 874 pt window (an iPhone 18 Pro screen), its parts' frames read through
/// `ComposerLayoutProbe` (#854).
@MainActor
@Suite(.serialized)
struct ComposerLayoutHostedTests {
    /// Thirty lines: past the editor's six-line cap.
    private static let longText = (1...30).map { "Ligne \($0) du message." }.joined(separator: "\n")

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    private func host(size: DynamicTypeSize, text: String) async throws -> ProbeBox {
        let box = ProbeBox()
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let model = ComposerFixture.model(poster: ScriptedPoster([]))
        let view = ReplyComposerView(model: model) { _ in }
            .environment(\.dynamicTypeSize, size)
            .environment(\.composerLayoutProbe, box.probe)
            .appTypography(TextScale(percent: 100), density: .regular)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = UIHostingController(rootView: view)
        window.isHidden = false
        defer { window.isHidden = true }
        // Polls until the draft is read, then until the text is laid out (a cold simulator can take a while).
        for _ in 0..<100 where !model.canEdit { try await Task.sleep(for: .milliseconds(50)) }
        model.update(text: text)
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            if box.layout.text > 0, box.frames[.controls] != nil, box.frames[.card] != nil { break }
        }
        try await Task.sleep(for: .milliseconds(300))
        return box
    }

    /// On an iPhone the control row is the text card's bottom edge, under the editor capped at six lines, and the card is
    /// exactly `textCardHeight` tall; an iPad keeps the row under the card.
    @Test(arguments: [DynamicTypeSize.large, .xLarge])
    func theControlRowSitsInsideTheCardUnderTheCappedEditor(size: DynamicTypeSize) async throws {
        let box = try await host(size: size, text: Self.longText)
        let card = try #require(box.frames[.card])
        let editor = try #require(box.frames[.editor])
        let controls = try #require(box.frames[.controls])
        guard isPhone else {
            #expect(controls.minY >= card.maxY - 0.5, "an iPad keeps the row under the card")
            return
        }
        let layout = box.layout
        #expect(layout.text > ComposerCardLayout.maximumLines * layout.line, "the text is past the cap")
        #expect(abs(editor.height - layout.editorHeight) < 1, "editor \(editor.height), cap \(layout.editorHeight)")
        #expect(card.insetBy(dx: -0.5, dy: -0.5).contains(controls), "card \(card), controls \(controls)")
        #expect(controls.minY >= editor.maxY - 0.5, "editor \(editor), controls \(controls)")
        #expect(abs(card.height - layout.textCardHeight) < 1, "card \(card.height), textCardHeight \(layout.textCardHeight)")
    }

    /// The title never sits under a floating button, at the default size or an accessibility one, and each button keeps a
    /// 44 pt hit area although its capsule is drawn smaller (operator, 2026-11-13).
    @Test(arguments: [DynamicTypeSize.large, .accessibility3])
    func theTitleNeverSitsUnderAFloatingButton(size: DynamicTypeSize) async throws {
        guard isPhone else { return }
        let box = try await host(size: size, text: "Bonjour")
        let title = try #require(box.frames[.title])
        #expect(title.width > 0)
        for part in [ComposerLayoutProbe.Part.close, .drafts, .send] {
            let button = try #require(box.frames[part], "\(part) is shown")
            #expect(!button.intersects(title), "\(part) \(button), title \(title)")
            #expect(button.width >= ComposerHeader.hitSize - 0.5 && button.height >= ComposerHeader.hitSize - 0.5, "\(part) \(button)")
        }
    }
}
