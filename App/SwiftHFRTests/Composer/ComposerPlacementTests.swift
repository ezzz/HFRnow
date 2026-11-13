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
    @Test(arguments: [true, false], [UserInterfaceSizeClass.compact, .regular])
    func theReaderDocksItsComposersOnlyOnAnIPhoneInCompactWidth(isPhone: Bool, width: UserInterfaceSizeClass) {
        // Regular width on an iPhone is a Pro Max in landscape: the list column beside a docked bar could tear the reader down.
        let expected: ComposerPlacement = isPhone && width == .compact ? .docked : .sheet
        #expect(ComposerPlacement.reader(isPhone: isPhone, horizontalSizeClass: width) == expected)
    }

    @Test func thePageSeesAComposerOnlyWhileItIsDockedAndOpenAtItsHeight() {
        typealias Presenter = ReaderComposerPresenter
        #expect(Presenter.docked(isDocked: true, composerIsOpen: true, height: nil) == .partial, "before the composer reports")
        #expect(Presenter.docked(isDocked: true, composerIsOpen: true, height: .partial) == .partial)
        #expect(Presenter.docked(isDocked: true, composerIsOpen: true, height: .full) == .full)
        #expect(Presenter.docked(isDocked: true, composerIsOpen: false, height: .full) == nil)
        #expect(Presenter.docked(isDocked: false, composerIsOpen: true, height: .partial) == nil, "a sheet")
    }

    @Test func theBottomBarMakesWayOnlyForAnOpenDockedComposer() {
        #expect(ReaderComposerGuard.hidesBottomBar(placement: .docked, composerIsOpen: true))
        #expect(!ReaderComposerGuard.hidesBottomBar(placement: .docked, composerIsOpen: false))
        #expect(!ReaderComposerGuard.hidesBottomBar(placement: .sheet, composerIsOpen: true))
    }

    /// The page's web view reads the docked composer from its environment: a drag down on it pulls the keyboard down.
    @Test func underADockedComposerDraggingThePageDownPullsTheKeyboardDown() async throws {
        let (controller, recorder) = makeController(transport: MockTransport(replies: []))
        recorder.window?.isHidden = true
        let state = DockedState()
        let host = UIHostingController(rootView: WebHost(controller: controller, state: state))
        let window = try #require(Self.window(host))
        defer { window.isHidden = true }
        let scroll = controller.webView.scrollView
        #expect(scroll.keyboardDismissMode == UIScrollView.KeyboardDismissMode.none)
        state.docked = .partial
        await Self.waitUntil { scroll.keyboardDismissMode == .interactive }
        #expect(scroll.keyboardDismissMode == UIScrollView.KeyboardDismissMode.interactive)
        state.docked = nil
        await Self.waitUntil { scroll.keyboardDismissMode == .none }
        #expect(scroll.keyboardDismissMode == UIScrollView.KeyboardDismissMode.none, "the page prompt's keyboard is left alone")
    }

    /// At partial height the bar's inset reaches the page; when the bar covers the page its insets are the ones it had with no
    /// docked composer, never the whole viewport, even in the first pass where the bar is already full and the composer has not
    /// said so yet (still `.partial`).
    @Test func underAFullHeightComposerThePageKeepsItsInsets() async throws {
        let state = DockedState()
        let seen = SeenInsets()
        let host = UIHostingController(rootView: InsetsHost(state: state, seen: seen))
        let window = try #require(Self.window(host))
        defer { window.isHidden = true }
        await Self.waitUntil { seen.bottom != nil }
        let base = try #require(seen.bottom) // the window's own bottom safe area
        state.bar = 200
        state.docked = .partial
        await Self.waitUntil { abs((seen.bottom ?? 0) - base - 200) < 1 }
        #expect(abs((seen.bottom ?? 0) - base - 200) < 1, "partial: \(seen.bottom ?? -1)")
        state.bar = 0
        state.docked = nil
        await Self.waitUntil { abs((seen.bottom ?? 0) - base) < 1 }
        // The first pass of a full-height opening: the bar covers the page, the composer has not reported its height yet.
        state.bar = 820
        state.docked = .partial
        try await Task.sleep(for: .milliseconds(200))
        #expect(abs((seen.bottom ?? 0) - base) < 1, "covered, before the height is known: \(seen.bottom ?? -1)")
        state.docked = .full
        try await Task.sleep(for: .milliseconds(200))
        #expect(abs((seen.bottom ?? 0) - base) < 1, "full: \(seen.bottom ?? -1)")
        state.bar = 250
        state.docked = .partial
        await Self.waitUntil { abs((seen.bottom ?? 0) - base - 250) < 1 }
        #expect(abs((seen.bottom ?? 0) - base - 250) < 1, "partial again: \(seen.bottom ?? -1)")
    }

    /// A docked composer closes through its presenter: `onClose` once, the binding cleared, and the reader it sits in (a pushed
    /// screen of a `NavigationStack`) stays: a `dismiss()` there would pop it.
    @Test(.enabled(if: UIDevice.current.userInterfaceIdiom == .phone))
    func aDockedComposerClosesOnceAndLeavesTheReaderOnScreen() async throws {
        let composer = ComposerFixture.model(poster: ScriptedPoster([]))
        let state = PresentedComposer(composer)
        state.path = [1]
        let host = UIHostingController(rootView: StackHost(state: state))
        let window = try #require(Self.window(host))
        defer { window.isHidden = true }
        _ = try #require(await Self.waitForTextView(in: host.view))
        await composer.start()
        await composer.requestClose()
        await Self.waitUntil { state.composer == nil }
        await Self.waitUntil { Self.textView(in: host.view) == nil } // the bar slides out
        try await Task.sleep(for: .milliseconds(300))
        #expect(state.closes.count == 1, "\(state.closes)")
        #expect(state.composer == nil)
        #expect(state.path == [1], "the reader is still pushed")
        #expect(Self.textView(in: host.view) == nil)
    }

    /// The docked bar is part of the reader's own screen: the page's safe area ends at the bar's top (the last lines are
    /// reachable), a touch above it goes to the page, one on it does not, and the bar stays when the keyboard goes.
    @Test(.enabled(if: UIDevice.current.userInterfaceIdiom == .phone))
    func aDockedComposerLeavesThePageAboveItLiveAndStaysWhenTheKeyboardGoes() async throws {
        let composer = ComposerFixture.model(poster: ScriptedPoster([]))
        let state = PresentedComposer(composer)
        let seen = SeenInsets()
        let host = UIHostingController(rootView: DockHost(state: state, seen: seen))
        let window = try #require(Self.window(host))
        defer { window.isHidden = true }
        let textView = try #require(await Self.waitForTextView(in: host.view))
        try await Task.sleep(for: .milliseconds(200))
        let card = textView.convert(textView.bounds, to: window)
        #expect(textView.window === window, "in the reader's own window, not a presented sheet")
        // The bar's top as touches see it: the first point above the text where the page takes the touch.
        let x = window.bounds.midX
        var barTop = card.minY
        while barTop > 0, !Self.isInScrollView(window.hitTest(CGPoint(x: x, y: barTop - 1), with: nil)) { barTop -= 1 }
        #expect(barTop < card.minY - 20, "the bar's header and its background take the touches: \(barTop) vs \(card.minY)")
        #expect(barTop > window.bounds.midY, "the bar sits at the bottom: \(barTop)")
        let inset = try #require(seen.bottom)
        #expect(abs(window.bounds.maxY - inset - barTop) <= 1, "the page's bottom inset reaches the bar's top: \(inset), \(barTop)")
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

    private static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() { try? await Task.sleep(for: .milliseconds(20)) }
    }

    private static func waitForTextView(in view: UIView) async -> UITextView? {
        await waitUntil { textView(in: view) != nil }
        return textView(in: view)
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
    var bottom: CGFloat? {
        didSet { if let bottom { largest = max(largest ?? bottom, bottom) } }
    }
    /// The largest bottom inset handed to the page so far.
    var largest: CGFloat?
}

@MainActor
@Observable
private final class DockedState {
    var docked: DockedComposer?
    var bar: CGFloat = 0
}

@MainActor
@Observable
private final class PresentedComposer {
    var composer: ReplyComposerModel?
    var closes: [ReplyComposerModel.CloseReason] = []
    var path: [Int] = []
    var placement = ComposerPlacement.docked
    init(_ composer: ReplyComposerModel?) { self.composer = composer }
}

/// The reader's page as `TopicReaderView` lays it out, over a stand-in scroll view.
private struct Page: View {
    let seen: SeenInsets

    var body: some View {
        ReaderUnderBars { insets in
            seen.bottom = insets.bottom
            return ScrollView { Color.gray.frame(height: 3_000) }
        }
    }
}

/// The reader's presenter, docked, over the page.
private struct DockHost: View {
    @Bindable var state: PresentedComposer
    let seen: SeenInsets

    var body: some View {
        Page(seen: seen).modifier(ReaderComposerPresenter(composer: $state.composer, placement: state.placement) { _, reason in
            state.closes.append(reason)
        })
    }
}

/// The docked presenter in a reader pushed on a `NavigationStack`, as `ReaderColumn` hosts it.
private struct StackHost: View {
    @Bindable var state: PresentedComposer

    var body: some View {
        NavigationStack(path: $state.path) {
            Text("Liste").navigationDestination(for: Int.self) { _ in
                DockHost(state: state, seen: SeenInsets())
            }
        }
    }
}

/// A page under a stand-in bar of `state.bar` points, with `state.docked` as the presenter would set it.
private struct InsetsHost: View {
    let state: DockedState
    let seen: SeenInsets

    var body: some View {
        Page(seen: seen)
            .environment(\.dockedComposer, state.docked)
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.red.frame(height: state.bar) }
    }
}

/// The reader's web view with `state.docked` as the presenter would set it.
private struct WebHost: View {
    let controller: ReaderWebController
    let state: DockedState

    var body: some View {
        ReaderWebView(controller: controller, document: nil, scrollRequest: nil)
            .environment(\.dockedComposer, state.docked)
    }
}

// The presenter's paths that a rotation or a full-height opening take (review rounds of #853).
extension ComposerPlacementTests {
    /// A composer opened at full height (an accessibility text size opens it full) covers the page from its first pass: the page's
    /// bottom inset never grows to the viewport, whatever order the bar's layout and its height report come in.
    @Test(.enabled(if: UIDevice.current.userInterfaceIdiom == .phone))
    func aComposerOpenedAtFullHeightNeverHandsThePageTheViewport() async throws {
        let state = PresentedComposer(nil)
        let seen = SeenInsets()
        let root = DockHost(state: state, seen: seen).environment(\.dynamicTypeSize, .accessibility3)
        let host = UIHostingController(rootView: root)
        let window = try #require(Self.window(host))
        defer { window.isHidden = true }
        await Self.waitUntil { seen.bottom != nil }
        let base = try #require(seen.bottom)
        seen.largest = nil
        state.composer = ComposerFixture.model(poster: ScriptedPoster([]))
        _ = try #require(await Self.waitForTextView(in: host.view))
        try await Task.sleep(for: .milliseconds(400))
        let card = try #require(Self.textView(in: host.view)).convert(CGRect.zero, to: window)
        #expect(card.minY < window.bounds.midY, "opened full: the editor starts in the top half (\(card.minY))")
        #expect((seen.largest ?? 0) <= base + 1, "the largest bottom inset handed to the page: \(seen.largest ?? -1), base \(base)")
    }

    /// A rotation moves the open composer between the bar and a sheet (Pro Max: compact to regular width and back): it stays
    /// open, nothing closes it, and one editor is left in the end.
    @Test(.enabled(if: UIDevice.current.userInterfaceIdiom == .phone))
    func aWidthChangeMovesTheComposerBetweenTheBarAndASheetWithoutClosingIt() async throws {
        let composer = ComposerFixture.model(poster: ScriptedPoster([]))
        let state = PresentedComposer(composer)
        let host = UIHostingController(rootView: DockHost(state: state, seen: SeenInsets()))
        let window = try #require(Self.window(host))
        defer { window.isHidden = true }
        _ = try #require(await Self.waitForTextView(in: host.view))
        state.placement = .sheet
        await Self.waitUntil { host.presentedViewController.map { Self.textView(in: $0.view) != nil } ?? false }
        #expect(host.presentedViewController != nil, "a sheet")
        #expect(Self.textView(in: host.view) == nil, "the bar is gone")
        state.placement = .docked
        await Self.waitUntil { host.presentedViewController == nil && Self.textView(in: host.view) != nil }
        try await Task.sleep(for: .milliseconds(300))
        #expect(state.composer === composer)
        #expect(state.closes.isEmpty, "\(state.closes)")
        #expect(host.presentedViewController == nil)
        #expect(Self.textViews(in: window) == 1)
    }

    /// The presenter watches the close for its sheet too: `onClose` once, the binding cleared, the sheet dismissed.
    @Test func aSheetComposerClosesOnceThroughItsPresenter() async throws {
        let composer = ComposerFixture.model(poster: ScriptedPoster([]))
        let state = PresentedComposer(composer)
        state.placement = .sheet
        let host = UIHostingController(rootView: DockHost(state: state, seen: SeenInsets()))
        let window = try #require(Self.window(host))
        defer { window.isHidden = true }
        await Self.waitUntil { host.presentedViewController != nil }
        await composer.start()
        await composer.requestClose()
        await Self.waitUntil { state.composer == nil && host.presentedViewController == nil }
        try await Task.sleep(for: .milliseconds(300))
        #expect(state.closes.count == 1, "\(state.closes)")
        #expect(state.composer == nil)
        #expect(host.presentedViewController == nil)
    }

    private static func textViews(in view: UIView) -> Int {
        (view is UITextView ? 1 : 0) + view.subviews.reduce(0) { $0 + textViews(in: $1) }
    }
}
