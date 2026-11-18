import HFRStorage
import SwiftUI
@testable import SwiftHFR
import Testing
import UIKit

@MainActor
private final class ProbeBox {
    var frames: [ComposerLayoutProbe.Part: CGRect] = [:]
    var layout = ComposerCardLayout()
    /// The hosting window's usable horizontal range: the screen's width less its side safe-area insets (the iPhone Duo cover
    /// screen keeps 84 pt on its trailing side for the system bars), whatever the device (#1084).
    var leadingEdge: CGFloat = 0
    var trailingEdge: CGFloat = 0
    var midX: CGFloat { (leadingEdge + trailingEdge) / 2 }

    var probe: ComposerLayoutProbe {
        ComposerLayoutProbe(frame: { [weak self] part, frame in self?.frames[part] = frame }, layout: { [weak self] in self?.layout = $0 })
    }
}

/// The real reply composer hosted in a window the size of the screen (402 × 874 pt on an iPhone 18 Pro), its parts' frames
/// read through `ComposerLayoutProbe` (#854).
@MainActor
@Suite(.serialized)
struct ComposerLayoutHostedTests {
    /// Thirty lines: past the editor's six-line cap.
    private static let longText = (1...30).map { "Ligne \($0) du message." }.joined(separator: "\n")

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    private func host(
        size: DynamicTypeSize, text: String, model: ReplyComposerModel = ComposerFixture.model(poster: ScriptedPoster([])),
        placement: ComposerPlacement = .sheet
    ) async throws -> ProbeBox {
        let box = ProbeBox()
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        // The modern composer's layout (#854, #895): its switch is off by default since #855.
        let settings = ExperimentalSettings(store: InMemorySettingsStore())
        settings.set(.modernComposer, isOn: true)
        let view = ReplyComposerView(model: model, placement: placement) { _ in }
            .environment(settings)
            .environment(\.dynamicTypeSize, size)
            .environment(\.composerLayoutProbe, box.probe)
            .appTypography(TextScale(percent: 100), density: .regular)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: view)
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        box.leadingEdge = window.safeAreaInsets.left
        box.trailingEdge = window.bounds.width - window.safeAreaInsets.right
        // Polls until the draft is read, then until the text is laid out (a cold simulator can take a while).
        for _ in 0..<100 where !model.canEdit { try await Task.sleep(for: .milliseconds(50)) }
        model.update(text: text)
        // Then until the frames stop moving (four equal reads in a row): the state the tests measure, not a fixed delay.
        var last: [ComposerLayoutProbe.Part: CGRect] = [:]
        var steady = 0
        for _ in 0..<150 where steady < 4 {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            let ready = box.layout.text > 0 && box.frames[.controls] != nil && box.frames[.card] != nil
            steady = ready && box.frames == last ? steady + 1 : 0
            last = box.frames
        }
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

    /// No title strip (#972): close and drafts on the left, send on the right, in one row directly above the card, each keeping
    /// a 44 pt hit area although its capsule is drawn smaller (operator, 2026-11-13), at the default size and an accessibility one.
    @Test(arguments: [DynamicTypeSize.large, .accessibility3])
    func theFloatingButtonsSitAboveTheCardWithNoTitle(size: DynamicTypeSize) async throws {
        guard isPhone else { return }
        let box = try await host(size: size, text: "Bonjour")
        #expect(box.frames[.title] == nil, "no title is drawn")
        let card = try #require(box.frames[.card])
        let close = try #require(box.frames[.close])
        let drafts = try #require(box.frames[.drafts])
        let send = try #require(box.frames[.send])
        for (part, button) in [("close", close), ("drafts", drafts), ("send", send)] {
            #expect(button.width >= ComposerHeader.hitSize - 0.5 && button.height >= ComposerHeader.hitSize - 0.5, "\(part) \(button)")
            #expect(button.maxY <= card.minY + 0.5, "\(part) \(button), card \(card)")
        }
        #expect(close.maxX <= drafts.minX + 0.5, "close \(close), drafts \(drafts)")
        #expect(drafts.maxX <= send.minX + 0.5, "the left group ends before send: drafts \(drafts), send \(send)")
        // The buttons are the card tools' size (#1126): at an accessibility size their hit areas outgrow half the width.
        if size == .large { #expect(drafts.maxX < box.midX && send.minX > box.midX, "drafts \(drafts), send \(send)") }
        #expect(abs(close.midY - send.midY) < 0.5, "one row: close \(close), send \(send)")
        // Nothing but the row above the card: no strip of its own (a title over or under the buttons would add one).
        let diameter = ComposerToolSize(metrics: ComposerBarMetrics(density: .regular, scale: TextScale(percent: 100))).diameter
        let insets = ComposerChrome.docked.headerInsets(diameter: diameter)
        guard size == .large else { return }
        #expect(abs(box.layout.top - (ComposerHeader.hitSize + insets.top + insets.bottom)) < 0.5, "top \(box.layout.top)")
    }

    /// The reader's docked bar leaves the buttons' row unfilled (#972): its opaque fill starts at the row's bottom edge, so the
    /// page shows around the buttons, and covers the card.
    @Test func theDockedBarsFillStartsUnderTheButtonsRow() async throws {
        guard isPhone else { return }
        let box = try await host(size: .large, text: "Bonjour", placement: .docked)
        let fill = try #require(box.frames[.fill])
        let close = try #require(box.frames[.close])
        let card = try #require(box.frames[.card])
        let diameter = ComposerToolSize(metrics: ComposerBarMetrics(density: .regular, scale: TextScale(percent: 100))).diameter
        let rowBottom = close.maxY + ComposerChrome.docked.headerInsets(diameter: diameter).bottom
        #expect(abs(fill.minY - rowBottom) < 0.5, "fill \(fill), close \(close)")
        #expect(fill.minY <= card.minY + 0.5 && fill.maxY >= card.maxY - 0.5, "fill \(fill), card \(card)")
    }

    /// The modern composer's margins as laid out (#895): the text card is `FloatingSpacing.gap` from the window's sides, and the
    /// close capsule (drawn around the card tools' glyph, inside its 44 pt hit area) is the gap from the side and from the card.
    @Test func theCardAndTheFloatingButtonsAreTheSharedGapFromTheEdges() async throws {
        guard isPhone else { return }
        let box = try await host(size: .large, text: "Bonjour")
        let card = try #require(box.frames[.card])
        let close = try #require(box.frames[.close])
        let gap = FloatingSpacing.gap
        #expect(abs(card.minX - box.leadingEdge - gap) < 0.5, "card \(card)")
        #expect(abs(box.trailingEdge - card.maxX - gap) < 0.5, "card \(card)")
        #expect(close.width >= ComposerHeader.hitSize - 0.5 && close.height >= ComposerHeader.hitSize - 0.5, "close \(close)")
        let tool = ComposerToolSize(metrics: ComposerBarMetrics(density: .regular, scale: TextScale(percent: 100)))
        let capsule = ComposerHeader.capsuleSize(diameter: tool.diameter)
        #expect(abs(close.midX - capsule.width / 2 - box.leadingEdge - gap) < 0.5, "close \(close)")
        #expect(abs(card.minY - (close.midY + capsule.height / 2) - gap) < 0.5, "close \(close), card \(card)")
    }

    /// One icon size (#895): the close button's glyph is drawn at the card tools' point size and weight (#1126,
    /// `ComposerToolSize.glyphWeight`), measured against the same symbol drawn by UIKit at that size and weight (a
    /// `.subheadline` bold glyph, the size before #895, is about 4 pt smaller).
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

    /// #1126: the close button's drawn circle is the card tools' chip diameter on both axes (the base drew a 39 × 31 pt capsule).
    @Test func theFloatingButtonIsTheCardToolsDiameter() async throws {
        guard isPhone else { return }
        let box = try await host(size: .large, text: "Bonjour")
        let circle = try #require(box.frames[.closeCircle])
        let tool = ComposerToolSize(metrics: ComposerBarMetrics(density: .regular, scale: TextScale(percent: 100)))
        #expect(abs(circle.width - tool.diameter) < 0.5, "circle \(circle), chip \(tool.diameter)")
        #expect(abs(circle.height - tool.diameter) < 0.5, "circle \(circle), chip \(tool.diameter)")
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
