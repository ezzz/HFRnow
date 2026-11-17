import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

@MainActor
private final class OffProbeBox {
    var frames: [ComposerLayoutProbe.Part: CGRect] = [:]

    var probe: ComposerLayoutProbe {
        ComposerLayoutProbe(frame: { [weak self] part, frame in self?.frames[part] = frame }, layout: { _ in })
    }
}

@MainActor
@Observable
private final class OffReaderState {
    var composer: ReplyComposerModel?
    var docked: DockedComposer?
    init(_ composer: ReplyComposerModel?) { self.composer = composer }
}

/// The reader's presenter with no forced placement, as the reply, edit and author-menu MP flows attach it.
private struct OffReader: View {
    @Bindable var state: OffReaderState

    var body: some View {
        OffPage(state: state).modifier(ReaderComposerPresenter(composer: $state.composer) { _, _ in })
    }
}

private struct OffPage: View {
    let state: OffReaderState
    @Environment(\.dockedComposer) private var docked

    var body: some View {
        Color.gray.onChange(of: docked, initial: true) { _, value in state.docked = value }
    }
}

/// #904's acceptance: with Réglages › Expérimental › « Composer moderne » off, nothing the option's folder brings runs, on
/// every composer entry point. The parts only `App/SwiftHFR/Experimental/ModernComposer/` draws report through
/// `ComposerLayoutProbe`:
/// - the floating close, drafts and send buttons and the close glyph (`FloatingComposerButtons`);
/// - the docked bar's fill (`DockedComposerBar`).
///
/// Its other parts are checked by their effect: the controls inside the card (`ComposerChrome`), the partial height
/// (`ComposerHeight`), the docked placement (`ComposerPlacement`). `ComposerPlacement.reader` itself runs on both paths: it is
/// the split. The switch on is the control twin: on an iPhone the probes see each part, so the off case cannot pass because a
/// probe went blind. An iPad never runs the modern composer.
@MainActor
@Suite(.serialized)
struct ModernComposerOffHostedTests {
    /// A composer's way in: a list's sheet (a new topic's, a reply's), a new MP's sheet, or the reader's presenter.
    enum Entry: CaseIterable, Sendable {
        case listSheet, newMessageSheet, reader
    }

    /// Drawn only by the option's folder.
    private static let modernOnlyParts: Set<ComposerLayoutProbe.Part> = [.close, .drafts, .send, .closeGlyph, .fill]
    /// Drawn by the floating buttons of every modern composer (drafts only where a topic archives drafts).
    private static let floatingParts: Set<ComposerLayoutProbe.Part> = [.close, .send, .closeGlyph]
    /// A window of an iPhone 18 Pro's size.
    private static let window = CGSize(width: 402, height: 874)

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    private struct Hosted {
        let box: OffProbeBox
        /// The reader's page: the docked composer it sees; nil for a list's sheet.
        let docked: DockedComposer?
        /// The reader's presentation, nil when the composer is the docked bar or a list's sheet.
        let presentation: UIModalPresentationStyle?
    }

    private func model(_ entry: Entry) -> ReplyComposerModel {
        switch entry {
        case .listSheet, .reader:
            ComposerFixture.model(poster: ScriptedPoster([]))
        case .newMessageSheet:
            ReplyComposerModel(
                composing: .newPrivateMessage(newMessageTarget), services: ComposerFixture.services(poster: ScriptedPoster([])),
                autosaveDelay: .seconds(60)
            )
        }
    }

    private func host(_ entry: Entry, modernComposer: Bool) async throws -> Hosted {
        let box = OffProbeBox()
        let settings = ExperimentalSettings(store: InMemorySettingsStore())
        settings.set(.modernComposer, isOn: modernComposer)
        let model = model(entry)
        let state = OffReaderState(model)
        let root: AnyView = switch entry {
        case .listSheet, .newMessageSheet: AnyView(ReplyComposerView(model: model, placement: .sheet) { _ in })
        case .reader: AnyView(OffReader(state: state))
        }
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let controller = UIHostingController(
            rootView: root
                .environment(settings)
                .environment(\.composerLayoutProbe, box.probe)
                .appTypography(TextScale(percent: 100), density: .regular)
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: Self.window)
        window.rootViewController = controller
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
        let presentation = entry == .reader ? controller.presentedViewController?.modalPresentationStyle : nil
        return Hosted(box: box, docked: entry == .reader ? state.docked : nil, presentation: presentation)
    }

    @Test(arguments: Entry.allCases, [false, true])
    func theOptionsFolderRunsOnlyWithTheSwitchOnAnIPhone(entry: Entry, modernComposer: Bool) async throws {
        let modern = isPhone && modernComposer
        let hosted = try await host(entry, modernComposer: modernComposer)
        let frames = hosted.box.frames
        let card = try #require(frames[.card], "the composer is laid out")
        let controls = try #require(frames[.controls])
        let drawn = Set(frames.keys)
        if modern {
            // The control twin: the probes see the folder's parts.
            #expect(Self.floatingParts.isSubset(of: drawn), "\(entry): \(drawn)")
            #expect(card.insetBy(dx: -0.5, dy: -0.5).contains(controls), "\(entry): controls in the card")
            #expect(frames[.title] == nil, "\(entry): no title strip (#972)")
            #expect(card.height < Self.window.height / 2, "\(entry): partial height, card \(card)")
            if entry == .reader {
                #expect(frames[.fill] != nil, "the docked bar")
                #expect(hosted.docked == .partial)
                #expect(hosted.presentation == nil, "docked, not presented")
            }
        } else {
            #expect(drawn.isDisjoint(with: Self.modernOnlyParts), "\(entry): \(drawn.intersection(Self.modernOnlyParts))")
            #expect(frames[.title] != nil, "\(entry): legacy's bar and its title")
            #expect(controls.minY >= card.maxY - 0.5, "\(entry): the row under the card, card \(card), controls \(controls)")
            #expect(card.height >= Self.window.height / 2, "\(entry): full height, card \(card)")
            if entry == .reader {
                #expect(hosted.docked == nil, "the page sees no docked composer")
                let presentation = try #require(hosted.presentation, "presented")
                if isPhone { #expect(presentation == .fullScreen, "legacy's cover") }
            }
        }
    }
}
