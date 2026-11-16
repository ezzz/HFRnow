import HFRStorage
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

    private func host(
        size: DynamicTypeSize, text: String, model: ReplyComposerModel = ComposerFixture.model(poster: ScriptedPoster([]))
    ) async throws -> ProbeBox {
        let box = ProbeBox()
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        // The modern composer's layout (#854, #895): its switch is off by default since #855.
        let settings = ExperimentalSettings(store: InMemorySettingsStore())
        settings.set(.modernComposer, isOn: true)
        let view = ReplyComposerView(model: model) { _ in }
            .environment(settings)
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

    /// The modern composer's margins as laid out (#895): the text card is `FloatingSpacing.gap` from the window's sides, and the
    /// close capsule (drawn around the card tools' glyph, inside its 44 pt hit area) is the gap from the side and from the card.
    @Test func theCardAndTheFloatingButtonsAreTheSharedGapFromTheEdges() async throws {
        guard isPhone else { return }
        let box = try await host(size: .large, text: "Bonjour")
        let card = try #require(box.frames[.card])
        let close = try #require(box.frames[.close])
        let gap = FloatingSpacing.gap
        #expect(abs(card.minX - gap) < 0.5, "card \(card)")
        #expect(abs(402 - card.maxX - gap) < 0.5, "card \(card)")
        #expect(close.width >= ComposerHeader.hitSize - 0.5 && close.height >= ComposerHeader.hitSize - 0.5, "close \(close)")
        let glyph = ComposerBarMetrics(density: .regular, scale: TextScale(percent: 100)).glyphSize
        let capsule = ComposerHeader.capsuleSize(glyph: glyph)
        #expect(abs(close.midX - capsule.width / 2 - gap) < 0.5, "close \(close)")
        #expect(abs(card.minY - (close.midY + capsule.height / 2) - gap) < 0.5, "close \(close), card \(card)")
    }

    /// One icon size (#895): the close button's glyph is drawn at the card tools' point size and weight, measured against the
    /// same symbol drawn by UIKit at that size (a `.subheadline` bold glyph, the size before #895, is about 4 pt smaller).
    @Test func theFloatingButtonsGlyphIsTheCardToolsSize() async throws {
        guard isPhone else { return }
        let box = try await host(size: .large, text: "Bonjour")
        let glyph = try #require(box.frames[.closeGlyph])
        let size = ComposerBarMetrics(density: .regular, scale: TextScale(percent: 100)).glyphSize
        let configuration = UIImage.SymbolConfiguration(pointSize: size, weight: .medium)
        let expected = try #require(UIImage(systemName: "xmark", withConfiguration: configuration)).size
        #expect(abs(glyph.height - expected.height) < 1, "glyph \(glyph), UIKit \(expected)")
        #expect(abs(glyph.width - expected.width) < 1, "glyph \(glyph), UIKit \(expected)")
    }

    /// A new private message has its recipient and subject between the floating buttons and the card: the card keeps the
    /// shared gap under them (#895, Fable round 1 on #936).
    @Test func underTheFieldsTheCardKeepsTheSharedGap() async throws {
        guard isPhone else { return }
        let model = ReplyComposerModel(
            composing: .newPrivateMessage(newMessageTarget), services: ComposerFixture.services(poster: ScriptedPoster([])),
            autosaveDelay: .seconds(60)
        )
        let box = try await host(size: .large, text: "Bonjour", model: model)
        let fields = try #require(box.frames[.fields])
        let card = try #require(box.frames[.card])
        #expect(abs(card.minY - fields.maxY - FloatingSpacing.gap) < 0.5, "fields \(fields), card \(card)")
    }
}
