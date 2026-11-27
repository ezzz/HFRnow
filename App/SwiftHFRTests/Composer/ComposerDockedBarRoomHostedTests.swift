import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// #1285, #1286: the docked bar's bottom stays on the keyboard (here the window's bottom safe area) whatever the page under it
/// needs (the presenter's backstop). The reader's page once had a minimum height (its bottom pull icon kept 96 pt under it, #1207,
/// about 135 pt measured on the iPhone 18 Pro simulator, iOS 27.2): once the bar and that minimum were taller than the space, the
/// stack overflowed both ways and the bar's bottom went behind the keyboard, past about 8 lines of a reply there. The source is
/// fixed in `ReaderStateOverlay` (`ReaderDockedComposerInsetsHostedTests`); this guards any other page.
@MainActor
@Suite(.serialized)
struct ComposerDockedBarRoomHostedTests {
    /// Thirty lines: the card at its cap.
    private static let longText = (1...30).map { "Ligne \($0) du message." }.joined(separator: "\n")

    /// A page as tall as the window allows, under a navigation bar, that cannot shrink below `minimum` points (as the reader's
    /// pull icons make it): the bar's card stays within the safe area, its bottom on the safe area's bottom edge, and the
    /// buttons above it below the navigation bar.
    @Test(.enabled(if: UIDevice.current.userInterfaceIdiom == .phone), arguments: [CGFloat(0), 135, 300])
    func theBarStaysAboveTheBottomEdgeWhateverThePageNeeds(minimum: CGFloat) async throws {
        let box = FramesBox()
        let model = ComposerFixture.model(poster: ScriptedPoster([]))
        let state = BarState(model)
        let host = UIHostingController(rootView: BarHost(state: state, minimum: minimum).environment(\.composerLayoutProbe, box.probe))
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        // Short enough that the capped card (six lines with no keyboard measured, about 254 pt) and the reader's 135 pt page do
        // not fit together under the navigation bar: the space a keyboard leaves on a phone (a window of this size has no safe area).
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 420)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<100 where !model.canEdit { try await Task.sleep(for: .milliseconds(20)) }
        model.update(text: Self.longText)
        // Until the frames stop moving (four equal reads in a row), the state measured, not a fixed delay (#1194).
        var last: [ComposerLayoutProbe.Part: CGRect] = [:]
        var steady = 0
        for _ in 0..<150 where steady < 4 {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            let ready = box.frames[.card] != nil && box.frames[.send] != nil && box.layout.text > 0
            steady = ready && box.frames == last ? steady + 1 : 0
            last = box.frames
        }
        try #require(steady >= 4, "frames never settled: \(box.frames)")
        let card = try #require(box.frames[.card])
        let send = try #require(box.frames[.send])
        let bottom = window.bounds.maxY - host.view.safeAreaInsets.bottom
        let navigationBar = try #require(Self.navigationBar(in: window))
        let navigationBottom = navigationBar.maxY
        // The room estimate's navigation bar is the one laid out (#1286: 54 pt on iOS 27.2, not the HIG's 44 pt).
        #expect(
            abs(navigationBar.height - ComposerCardLayout.navigationBarHeight) < 0.5,
            "the navigation bar is \(navigationBar.height) pt, the room assumes \(ComposerCardLayout.navigationBarHeight)"
        )
        #expect(abs(card.height - box.layout.textCardHeight) < 1, "the card at its cap: \(card.height), \(box.layout.textCardHeight)")
        // The gap under the card is the modern chrome's (`ComposerChrome.cardInsets`).
        let gap = ComposerChrome.docked.cardInsets.bottom
        #expect(abs(card.maxY + gap - bottom) < 1, "the card's bottom \(card.maxY) + \(gap) on the bottom edge \(bottom)")
        #expect(send.minY >= navigationBottom - 0.5, "the buttons \(send) under the navigation bar \(navigationBottom)")
    }

    /// The navigation bar's frame in window coordinates.
    private static func navigationBar(in view: UIView) -> CGRect? {
        if let bar = view as? UINavigationBar, let window = bar.window { return bar.convert(bar.bounds, to: window) }
        return view.subviews.lazy.compactMap { navigationBar(in: $0) }.first
    }
}

@MainActor
private final class FramesBox {
    var frames: [ComposerLayoutProbe.Part: CGRect] = [:]
    var layout = ComposerCardLayout()

    var probe: ComposerLayoutProbe {
        ComposerLayoutProbe(frame: { [weak self] part, frame in self?.frames[part] = frame }, layout: { [weak self] in self?.layout = $0 })
    }
}

@MainActor
@Observable
private final class BarState {
    var composer: ReplyComposerModel?
    /// « Composer moderne » on: the docked bar is its own (its default is off since #855).
    let settings = ExperimentalSettings(store: InMemorySettingsStore())

    init(_ composer: ReplyComposerModel) {
        self.composer = composer
        settings.set(.modernComposer, isOn: true)
    }
}

/// The reader's layout in short: a page under an inline navigation bar, the docked presenter on it. The page fills what it is
/// given and cannot be shorter than `minimum`, as `ReaderStateOverlay`'s bottom pull icon once made the reader's.
private struct BarHost: View {
    @Bindable var state: BarState
    let minimum: CGFloat

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView { Color.gray.frame(height: 3_000) }
                Color.clear.frame(height: 1).padding(.bottom, max(0, minimum - 1))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .navigationTitle("Sujet")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(ReaderComposerPresenter(composer: $state.composer, placement: .docked) { _, _ in })
        }
        .environment(state.settings)
        // A short window reads as compact height, where the composer opens full: a phone in portrait, keyboard up, is regular.
        .environment(\.verticalSizeClass, .regular)
    }
}
