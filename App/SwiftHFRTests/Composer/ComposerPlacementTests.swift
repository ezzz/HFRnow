import Foundation
import HFRNetwork
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// Issue #853 (operator, 2026-11-13): on an iPhone the reader's composers are a bar docked at the bottom of the page, on the
/// keyboard, so the page above it scrolls with the keyboard up; dragging the page down pulls the keyboard down and the bar stays.
@MainActor
@Suite(.serialized)
struct ComposerPlacementTests: ReaderWebTesting {
    @Test(arguments: [true, false])
    func theReaderDocksItsComposersOnAnIPhoneOnly(isPhone: Bool) {
        #expect(ComposerPlacement.reader(isPhone: isPhone) == (isPhone ? .docked : .sheet))
    }

    @Test func thePageFollowsTheKeyboardOnlyUnderAnOpenDockedComposer() {
        #expect(ComposerPlacement.pageFollowsKeyboard(placement: .docked, composerIsOpen: true))
        #expect(!ComposerPlacement.pageFollowsKeyboard(placement: .docked, composerIsOpen: false), "the page prompt's keyboard")
        #expect(!ComposerPlacement.pageFollowsKeyboard(placement: .sheet, composerIsOpen: true), "an iPad's sheet")
        #expect(!ComposerPlacement.pageFollowsKeyboard(placement: .sheet, composerIsOpen: false))
    }

    /// The bar sits on the keyboard: the page's bottom inset must count the keyboard then, or its last lines stay under it.
    @Test func underADockedComposerThePageCountsTheKeyboardInItsInsets() {
        #expect(ReaderUnderBars<Color>.ignored(followsKeyboard: true) == [])
        #expect(ReaderUnderBars<Color>.ignored(followsKeyboard: false) == .keyboard)
    }

    /// The Messages and Claude apps' gesture: a drag down on the page pulls the keyboard down with the finger.
    @Test func underADockedComposerDraggingThePageDownPullsTheKeyboardDown() {
        let (controller, _) = makeController(transport: MockTransport(replies: []))
        #expect(controller.webView.scrollView.keyboardDismissMode == UIScrollView.KeyboardDismissMode.none)
        controller.dismissesKeyboardInteractively = true
        #expect(controller.webView.scrollView.keyboardDismissMode == UIScrollView.KeyboardDismissMode.interactive)
        controller.dismissesKeyboardInteractively = false
        #expect(controller.webView.scrollView.keyboardDismissMode == UIScrollView.KeyboardDismissMode.none)
    }

    /// The docked bar is part of the reader's own screen: the page above it is the topmost view there (scrolls, takes the drag),
    /// its safe area ends above the bar (the last lines are reachable), and the bar stays when the keyboard goes. An iPhone only:
    /// the only device that docks it, and the one whose composer opens at partial height.
    @Test(.enabled(if: UIDevice.current.userInterfaceIdiom == .phone))
    func aDockedComposerLeavesThePageAboveItLiveAndStaysWhenTheKeyboardGoes() async throws {
        let composer = ComposerFixture.model(poster: ScriptedPoster([]))
        let seen = SeenInsets()
        let page = ReaderUnderBars(followsKeyboard: true) { insets in
            seen.bottom = insets.bottom
            return ScrollView { Color.gray.frame(height: 3_000) }
        }
        let state = PresentedComposer(composer)
        let host = UIHostingController(rootView: DockHost(state: state, placement: .docked) { page })
        let window = try #require(Self.window(host))
        defer { window.isHidden = true }
        let textView = try #require(await Self.waitForTextView(in: host.view))
        let bar = textView.convert(textView.bounds, to: window)
        #expect(bar.minY > window.bounds.midY, "the card sits at the bottom: \(bar)")
        #expect(textView.window === window, "in the reader's own window, not a presented sheet")
        #expect((seen.bottom ?? 0) >= window.bounds.maxY - bar.minY, "the page's bottom inset reaches the bar: \(seen.bottom ?? 0)")
        let hit = window.hitTest(CGPoint(x: window.bounds.midX, y: 150), with: nil)
        #expect(Self.isInScrollView(hit), "the page above the bar takes the touches: \(String(describing: hit))")
        // The keyboard goes (a pull-down or "return"): the composer stays open with its text.
        window.endEditing(true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.composer != nil)
        #expect(Self.textView(in: host.view) != nil, "the bar is still there")
    }

    private static func window(_ host: UIViewController) -> UIWindow? {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene else {
            return nil
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        return window
    }

    private static func waitForTextView(in view: UIView) async -> UITextView? {
        for _ in 0..<100 {
            if let found = textView(in: view) { return found }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }

    private static func textView(in view: UIView) -> UITextView? {
        if let found = view as? UITextView { return found }
        for child in view.subviews { if let found = textView(in: child) { return found } }
        return nil
    }

    private static func isInScrollView(_ view: UIView?) -> Bool {
        var current = view
        while let candidate = current {
            if candidate is UIScrollView, !(candidate is UITextView) { return true }
            current = candidate.superview
        }
        return false
    }
}

@MainActor
private final class SeenInsets {
    var bottom: CGFloat?
}

@MainActor
@Observable
private final class PresentedComposer {
    var composer: ReplyComposerModel?
    init(_ composer: ReplyComposerModel) { self.composer = composer }
}

/// The reader's presenter over a stand-in page.
private struct DockHost<Page: View>: View {
    @Bindable var state: PresentedComposer
    let placement: ComposerPlacement
    @ViewBuilder let page: () -> Page

    var body: some View {
        page().modifier(ReaderComposerPresenter(composer: $state.composer, placement: placement) { _, _ in })
    }
}
